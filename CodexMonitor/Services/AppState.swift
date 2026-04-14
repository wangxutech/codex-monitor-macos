//
//  AppState.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import Foundation

/// 应用全局状态中心。
/// 负责账号持久化、敏感信息钥匙串读写、请求调度和菜单栏摘要计算。
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var accounts: [CodexAccountProfile] = []
    @Published private(set) var runtimeStates: [UUID: AccountRuntimeState] = [:]
    @Published private(set) var menuBarTitle = "Codex"

    private let storageKey = "saved.codex.accounts"
    private let defaults: UserDefaults
    private let keychain = KeychainService(service: "ai.zenarkflow.codexmonitor.accounts")
    private let api = CodexUsageAPI()
    private let subscriptionRefreshInterval: TimeInterval = 12 * 60 * 60

    /// 账号敏感配置常驻内存，避免每次刷新都重复访问钥匙串。
    private var credentialsByID: [UUID: CodexAccountCredential] = [:]

    /// 每个启用账号拥有独立的自动刷新循环，便于按账号粒度配置刷新间隔。
    private var refreshTasks: [UUID: Task<Void, Never>] = [:]

    /// 防止同一账号同时触发多次刷新请求。
    private var refreshingIDs = Set<UUID>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadAccounts()
        syncRefreshTasks()
        rebuildMenuBarTitle()
    }

    func invalidate() {
        refreshTasks.values.forEach { $0.cancel() }
        refreshTasks.removeAll()
    }

    func runtimeState(for accountID: UUID) -> AccountRuntimeState {
        runtimeStates[accountID] ?? AccountRuntimeState()
    }

    func draft(for accountID: UUID?) -> CodexAccountDraft {
        guard
            let accountID,
            let profile = accounts.first(where: { $0.id == accountID })
        else {
            return CodexAccountDraft()
        }

        return CodexAccountDraft(
            profile: profile,
            credential: credentialsByID[accountID] ?? .empty
        )
    }

    func saveAccount(from draft: CodexAccountDraft) throws -> UUID {
        let accountID = draft.id ?? UUID()
        let displayName = resolvedDisplayName(for: draft, accountID: accountID)
        let bearerToken = draft.credential.normalizedAuthorizationHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookie = draft.credential.cookie.trimmingCharacters(in: .whitespacesAndNewlines)

        guard bearerToken.isEmpty == false else {
            throw AppStateError.validation("请输入 Authorization Bearer Token。")
        }

        guard cookie.isEmpty == false else {
            throw AppStateError.validation("请输入 Cookie。")
        }

        let now = Date()
        let refreshInterval = max(15, min(draft.refreshIntervalSeconds, 3600))
        let profile = CodexAccountProfile(
            id: accountID,
            displayName: displayName,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            refreshIntervalSeconds: refreshInterval,
            isEnabled: draft.isEnabled,
            createdAt: accounts.first(where: { $0.id == accountID })?.createdAt ?? now,
            updatedAt: now
        )

        let credential = CodexAccountCredential(
            bearerToken: draft.credential.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines),
            cookie: cookie,
            clientVersion: draft.credential.clientVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            clientBuildNumber: draft.credential.clientBuildNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceID: draft.credential.deviceID.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionID: draft.credential.sessionID.trimmingCharacters(in: .whitespacesAndNewlines),
            language: draft.credential.language.trimmingCharacters(in: .whitespacesAndNewlines),
            userAgent: draft.credential.userAgent.trimmingCharacters(in: .whitespacesAndNewlines),
            additionalHeadersText: draft.credential.additionalHeadersText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        upsertProfile(profile)
        credentialsByID[accountID] = credential
        try persistProfiles()
        try persistCredential(credential, for: accountID)
        syncRefreshTasks()

        // 新增或修改后主动刷新一次，避免用户还要手动点刷新确认配置是否有效。
        Task {
            await self.refreshAccount(accountID)
        }

        return accountID
    }

    func deleteAccount(_ accountID: UUID) {
        accounts.removeAll { $0.id == accountID }
        runtimeStates.removeValue(forKey: accountID)
        credentialsByID.removeValue(forKey: accountID)
        refreshTasks[accountID]?.cancel()
        refreshTasks.removeValue(forKey: accountID)
        refreshingIDs.remove(accountID)

        do {
            try persistProfiles()
            try keychain.delete(account: accountID.uuidString)
        } catch {
            runtimeStates[accountID, default: AccountRuntimeState()].errorMessage = error.localizedDescription
        }

        rebuildMenuBarTitle()
    }

    func setAccountEnabled(_ accountID: UUID, isEnabled: Bool) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }

        accounts[index].isEnabled = isEnabled
        accounts[index].updatedAt = Date()

        do {
            try persistProfiles()
        } catch {
            runtimeStates[accountID, default: AccountRuntimeState()].errorMessage = error.localizedDescription
        }

        syncRefreshTasks()
        rebuildMenuBarTitle()
    }

    func refreshAllAccounts() {
        for account in accounts where account.isEnabled {
            Task {
                await self.refreshAccount(account.id)
            }
        }
    }

    func refreshAccount(_ accountID: UUID) async {
        guard accounts.contains(where: { $0.id == accountID }) else {
            return
        }

        guard refreshingIDs.insert(accountID).inserted else {
            return
        }

        defer {
            refreshingIDs.remove(accountID)
            rebuildMenuBarTitle()
        }

        runtimeStates[accountID, default: AccountRuntimeState()].isRefreshing = true
        runtimeStates[accountID, default: AccountRuntimeState()].errorMessage = nil

        guard let credential = credentialsByID[accountID] else {
            runtimeStates[accountID, default: AccountRuntimeState()].isRefreshing = false
            runtimeStates[accountID, default: AccountRuntimeState()].errorMessage = "没有找到账号凭据，请重新编辑该账号。"
            return
        }

        do {
            let snapshot = try await api.fetchUsage(with: credential)
            updateDisplayNameIfNeeded(for: accountID, email: snapshot.email)
            let existingState = runtimeStates[accountID] ?? AccountRuntimeState()
            let subscriptionSnapshot = await refreshSubscriptionIfNeeded(
                for: accountID,
                credential: credential,
                existingState: existingState
            )
            runtimeStates[accountID] = AccountRuntimeState(
                isRefreshing: false,
                lastUpdatedAt: snapshot.fetchedAt,
                snapshot: snapshot,
                subscriptionSnapshot: subscriptionSnapshot,
                errorMessage: nil
            )
        } catch {
            var state = runtimeStates[accountID] ?? AccountRuntimeState()
            state.isRefreshing = false
            state.errorMessage = error.localizedDescription
            runtimeStates[accountID] = state
        }
    }

    private func syncRefreshTasks() {
        let enabledIDs = Set(accounts.filter(\.isEnabled).map(\.id))

        for (accountID, task) in refreshTasks where enabledIDs.contains(accountID) == false {
            task.cancel()
            refreshTasks.removeValue(forKey: accountID)
        }

        for account in accounts where account.isEnabled {
            guard refreshTasks[account.id] == nil else {
                continue
            }

            refreshTasks[account.id] = Task { [weak self] in
                await self?.runRefreshLoop(for: account.id)
            }
        }
    }

    /// 订阅信息刷新频率远低于用量，因此这里会先判断缓存是否过期。
    /// 如果 12 小时内已经成功拉取过，则直接沿用旧快照，避免额外请求。
    private func refreshSubscriptionIfNeeded(
        for accountID: UUID,
        credential: CodexAccountCredential,
        existingState: AccountRuntimeState
    ) async -> AccountSubscriptionSnapshot? {
        if let snapshot = existingState.subscriptionSnapshot,
           Date().timeIntervalSince(snapshot.fetchedAt) < subscriptionRefreshInterval {
            return snapshot
        }

        do {
            return try await api.fetchSubscription(with: credential)
        } catch {
            // 订阅信息是辅助展示项，不应该因为它失败就把核心用量卡片打成错误态。
            // 因此这里保留旧值并静默降级，后续在下一个刷新周期继续重试。
            return existingState.subscriptionSnapshot
        }
    }

    /// 当用户只通过 curl 导入时，界面上不再要求额外填写账号名。
    /// 这里会优先沿用已有名称，否则先生成一个临时占位名，等待首次成功刷新后再替换为真实邮箱。
    private func resolvedDisplayName(for draft: CodexAccountDraft, accountID: UUID) -> String {
        let trimmedName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty == false {
            return trimmedName
        }

        if let existingName = accounts.first(where: { $0.id == accountID })?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), existingName.isEmpty == false {
            return existingName
        }

        return "待识别账号 \(accountID.uuidString.prefix(6))"
    }

    /// 如果当前显示名还是系统生成的占位名，首次拉取成功后自动替换成真实邮箱，
    /// 这样用户不需要额外维护账号名称，也能在菜单栏中看到可识别的信息。
    private func updateDisplayNameIfNeeded(for accountID: UUID, email: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }

        let currentName = accounts[index].displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentName.hasPrefix("待识别账号 ") else {
            return
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.isEmpty == false else {
            return
        }

        accounts[index].displayName = normalizedEmail
        accounts[index].updatedAt = Date()

        do {
            try persistProfiles()
        } catch {
            runtimeStates[accountID, default: AccountRuntimeState()].errorMessage = error.localizedDescription
        }
    }

    /// 独立账号的自动刷新循环。
    /// 每次循环都会重新读取当前账号配置，因此修改刷新间隔后无需重建整个应用状态。
    private func runRefreshLoop(for accountID: UUID) async {
        while Task.isCancelled == false {
            await refreshAccount(accountID)

            guard let account = accounts.first(where: { $0.id == accountID }) else {
                break
            }

            let interval = UInt64(max(15, account.refreshIntervalSeconds)) * 1_000_000_000
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                break
            }
        }
    }

    private func upsertProfile(_ profile: CodexAccountProfile) {
        if let index = accounts.firstIndex(where: { $0.id == profile.id }) {
            accounts[index] = profile
        } else {
            accounts.append(profile)
        }

        accounts.sort { $0.createdAt < $1.createdAt }
    }

    private func loadAccounts() {
        guard let data = defaults.data(forKey: storageKey) else {
            return
        }

        do {
            accounts = try JSONDecoder().decode([CodexAccountProfile].self, from: data)

            for profile in accounts {
                if let credentialData = try keychain.load(account: profile.id.uuidString) {
                    let credential = try JSONDecoder().decode(CodexAccountCredential.self, from: credentialData)
                    credentialsByID[profile.id] = credential
                }
            }
        } catch {
            accounts = []
            credentialsByID = [:]
            menuBarTitle = "Codex !"
            print("加载账号失败：\(error.localizedDescription)")
        }
    }

    private func persistProfiles() throws {
        let data = try JSONEncoder().encode(accounts)
        defaults.set(data, forKey: storageKey)
    }

    private func persistCredential(_ credential: CodexAccountCredential, for accountID: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        try keychain.save(data: data, account: accountID.uuidString)
    }

    private func rebuildMenuBarTitle() {
        if accounts.isEmpty {
            menuBarTitle = "Codex"
            return
        }

        let remainingValues = accounts
            .filter(\.isEnabled)
            .compactMap { runtimeStates[$0.id]?.snapshot?.summaryRemainingPercent }

        if let minimumRemaining = remainingValues.min() {
            menuBarTitle = "Codex \(minimumRemaining)%"
            return
        }

        let hasError = accounts.contains { runtimeStates[$0.id]?.errorMessage?.isEmpty == false }
        menuBarTitle = hasError ? "Codex !" : "Codex ..."
    }
}

enum AppStateError: LocalizedError {
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        }
    }
}
