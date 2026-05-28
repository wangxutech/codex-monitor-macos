//
//  AppState.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import AppKit
import Foundation

/// 账号列表的显示范围筛选。
/// 当前只有两种模式：
/// 1. 显示所有账号
/// 2. 只显示当前仍然“可用”的账号
///
/// 这里把筛选条件放到全局状态层，而不是只放在视图层，原因有两个：
/// 1. 菜单栏面板高度也要跟随筛选结果变化，不能只影响列表本身
/// 2. 顶部摘要、空状态、底部设置都需要共享同一份筛选值
enum AccountVisibilityFilter: String, CaseIterable, Identifiable {
    case allAccounts
    case availableAccounts

    var id: String {
        rawValue
    }

    /// 提供给下拉框直接展示的人类可读文案。
    var title: String {
        switch self {
        case .allAccounts:
            return "所有账号"
        case .availableAccounts:
            return "可用账号"
        }
    }
}

/// 账号套餐类型筛选。
/// 当前菜单栏只暴露用户最常见、最容易理解的三类：Pro、Plus、Free。
/// 如果后续接口返回 Team / Business / Enterprise 等扩展类型，在三项全选时仍然显示，避免默认状态误隐藏账号。
enum AccountPlanFilter: String, CaseIterable, Identifiable, Hashable {
    case pro
    case plus
    case free

    var id: String {
        rawValue
    }

    /// 底部 checkbox 展示文案。
    var title: String {
        switch self {
        case .pro:
            return "Pro"
        case .plus:
            return "Plus"
        case .free:
            return "Free"
        }
    }
}

/// 应用全局状态中心。
/// 这次重构后，GUI 不再维护自己的账号数据库，而是直接把 `~/.codex/accounts/registry.json`
/// 当作唯一事实来源。这样可以和 `codex-auth`、Codex CLI、Codex App 共用同一套账号状态。
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var accounts: [CodexRegistryAccount] = []
    @Published private(set) var runtimeStates: [String: AccountRuntimeState] = [:]
    @Published private(set) var activeAccountKey: String?
    @Published private(set) var menuBarTitle = "Codex"
    @Published private(set) var codexHomePath = "~/.codex"
    @Published private(set) var isLaunchingLogin = false
    @Published private(set) var loginErrorMessage: String?
    @Published private(set) var accountVisibilityFilter: AccountVisibilityFilter = .allAccounts
    @Published private(set) var enabledPlanFilters = Set(AccountPlanFilter.allCases)

    private let authStore: CodexAuthStore
    private let api: CodexUsageAPI
    private let subscriptionRefreshInterval: TimeInterval = 12 * 60 * 60
    private let automaticRefreshIntervalSeconds: UInt64 = 5 * 60
    private let loginWatchIntervalSeconds: UInt64 = 2
    private let loginWatchTimeoutSeconds: TimeInterval = 180

    /// 防止同一账号同时发起重复请求。
    private var refreshingAccountKeys = Set<String>()

    /// 全局自动刷新循环。
    /// 账号配置改成和 `codex-auth` 对齐后，不再有“每个账号各自 refresh interval”的持久化字段，
    /// 因此这里统一采用固定周期刷新。
    private var refreshLoopTask: Task<Void, Never>?

    /// 登录监视循环。
    /// 点击“添加账号”后，GUI 会后台观察 `auth.json` 是否变化，
    /// 一旦发现官方登录已经写入新结果，就自动同步到菜单栏列表。
    private var loginWatchTask: Task<Void, Never>?

    /// 当前正在运行的官方登录子进程。
    /// 保存这个句柄是为了让用户可以在菜单栏里直接取消登录，
    /// 避免没有完成浏览器授权时，界面一直停在“登录中”且无法再次发起登录。
    private var loginProcess: Process?

    init(
        authStore: CodexAuthStore = CodexAuthStore(),
        api: CodexUsageAPI = CodexUsageAPI()
    ) {
        self.authStore = authStore
        self.api = api
        self.codexHomePath = (try? authStore.resolveCodexHome().path) ?? "~/.codex"
        reloadFromDisk()
        startRefreshLoop()

        // 应用启动后主动尝试一次账号名称补全。
        // 这样即使用户直接打开菜单栏，不经过额外“登录/切换”操作，
        // 也能逐步把 `codex-auth` 同作用域下缺失的 Team 工作区名称补齐。
        Task {
            await refreshActiveAccountNamesIfNeeded()
        }
    }

    func invalidate() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        cancelLogin()
    }

    /// 供视图读取某个账号的当前运行时状态。
    func runtimeState(for accountKey: String) -> AccountRuntimeState {
        runtimeStates[accountKey] ?? AccountRuntimeState()
    }

    /// 供卡片判断当前账号是否为活动账号。
    func isActiveAccount(_ accountKey: String) -> Bool {
        activeAccountKey == accountKey
    }

    /// 当前筛选条件下实际需要展示的账号列表。
    /// 视图层、摘要文案和菜单栏高度都统一走这里，避免同一条件被复制三份后逐渐跑偏。
    var filteredAccounts: [CodexRegistryAccount] {
        accounts.filter { account in
            shouldDisplayAccount(account.accountKey)
        }
    }

    /// 当前筛选后可见账号数量。
    /// 单独抽出来是为了让菜单栏高度计算更直接，不需要每次重新遍历一遍数组。
    var filteredAccountCount: Int {
        filteredAccounts.count
    }

    /// 更新账号显示范围。
    /// 这里单独提供方法而不是暴露可写 `@Published`，这样后续如果要把筛选值持久化到本地，
    /// 只需要在这个入口里补逻辑即可，不会影响视图层调用。
    func updateAccountVisibilityFilter(_ filter: AccountVisibilityFilter) {
        accountVisibilityFilter = filter
    }

    /// 切换某个套餐类型是否展示。
    /// 保持入口集中在状态层，后续如果要把筛选值持久化到用户偏好，这里就是唯一改动点。
    func updatePlanFilter(_ filter: AccountPlanFilter, isEnabled: Bool) {
        if isEnabled {
            enabledPlanFilters.insert(filter)
        } else {
            enabledPlanFilters.remove(filter)
        }
    }

    /// 视图层通过这个方法生成 checkbox 绑定，避免直接暴露可写集合。
    func isPlanFilterEnabled(_ filter: AccountPlanFilter) -> Bool {
        enabledPlanFilters.contains(filter)
    }

    /// 判断某个账号当前是否仍然可用。
    /// 业务规则按产品要求处理：
    /// 1. 只要 5 小时限额剩余为 0，则不可用
    /// 2. 只要每周限额剩余为 0，则不可用
    /// 3. 如果某个账号当前还没有拿到任何额度快照，则暂时视为可用，避免刚启动时被错误隐藏
    func isAccountAvailable(_ accountKey: String) -> Bool {
        guard let snapshot = runtimeState(for: accountKey).snapshot else {
            return true
        }

        return snapshot.isAvailableForDisplay
    }

    /// 打开官方登录流程。
    /// 这里不直接造浏览器请求，而是调用 `codex login`，让官方客户端继续生成标准 `auth.json`。
    func launchLogin(deviceAuth: Bool) throws {
        // 新登录开始前先停止旧登录流程。
        // 这样即使上一次浏览器授权被用户关闭，也不会因为旧进程或旧监视任务残留而无法重新登录。
        cancelLogin()
        loginErrorMessage = nil

        let baselineFingerprint = try authStore.activeAuthFingerprint()
        let process = try authStore.startCodexLoginProcess(deviceAuth: deviceAuth) { url in
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
        loginProcess = process
        NSLog("CodexMonitor: 已创建登录监视任务，等待 auth.json 变化。")
        startLoginWatchLoop(baselineFingerprint: baselineFingerprint, process: process)
    }

    /// 取消当前登录流程。
    /// 这只会终止 GUI 启动的 `codex login` 子进程，不会删除任何已经存在的账号或 token。
    func cancelLogin() {
        loginWatchTask?.cancel()
        loginWatchTask = nil

        if let loginProcess, loginProcess.isRunning {
            loginProcess.terminate()
        }
        loginProcess = nil
        isLaunchingLogin = false
    }

    /// 清理已经展示过的登录错误。
    /// 视图层通过这个入口确认错误已经被用户看到，避免 SwiftUI 状态刷新时重复弹出同一条提示。
    func clearLoginErrorMessage() {
        loginErrorMessage = nil
    }

    /// 用户完成登录后，主动同步当前 `auth.json` 到 registry，并刷新活动账号的展示数据。
    func synchronizeCurrentLoginResult() async throws {
        let registry = try authStore.synchronizeActiveAuthIntoRegistry()
        applyRegistry(registry)
        await refreshActiveAccountNamesIfNeeded()

        if let activeAccountKey {
            await refreshAccount(activeAccountKey)
        }
    }

    /// 切换账号。
    /// 切换完成后写回 `~/.codex/auth.json` 与 `registry.json`，
    /// 但不会主动退出或重启官方 Codex App。
    /// 这样可以避免用户正在 Codex App 中执行任务时，被账号切换操作意外中断。
    /// 如果 Codex App 需要重新读取登录态，应由用户在合适时机手动重启。
    func switchAccount(_ accountKey: String) throws {
        try authStore.switchToAccount(accountKey: accountKey)
        reloadFromDisk(syncActiveAuth: false)

        // 切换后立即尝试补一次工作区名称。
        // 这和 `codex-auth switch` 切换后基于新活动账号继续刷名字的体验保持一致。
        Task {
            await self.refreshActiveAccountNamesIfNeeded()
        }
    }

    /// 删除账号。
    func deleteAccount(_ accountKey: String) throws {
        try authStore.deleteAccount(accountKey: accountKey)
        reloadFromDisk(syncActiveAuth: false)
    }

    /// 刷新全部账号。
    /// 这里先同步一次活动账号的 `auth.json`，尽量把最新 token 带回 registry 与快照文件。
    func refreshAllAccounts() {
        reloadFromDisk()

        for account in accounts {
            Task {
                await self.refreshAccount(account.accountKey)
            }
        }
    }

    /// 刷新单个账号。
    /// 成功后会把最新用量快照回写到 `registry.json`，保持和 `codex-auth` 的展示数据一致。
    func refreshAccount(_ accountKey: String) async {
        guard refreshingAccountKeys.insert(accountKey).inserted else {
            return
        }

        defer {
            refreshingAccountKeys.remove(accountKey)
            rebuildMenuBarTitle()
        }

        var currentState = runtimeStates[accountKey] ?? AccountRuntimeState()
        currentState.isRefreshing = true
        currentState.errorMessage = nil
        runtimeStates[accountKey] = currentState

        // 活动账号的 token 可能已经被 Codex 客户端静默刷新。
        // 刷新前先做一次同步，可以尽量减少“当前账号明明还有效，却因快照过期而 401”的情况。
        if activeAccountKey == accountKey {
            do {
                let registry = try authStore.synchronizeActiveAuthIntoRegistry()
                applyRegistry(registry)
            } catch {
                // 同步失败并不一定意味着当前账号无法请求，因此这里只记录日志语义并继续尝试读取快照。
                setError("同步当前 auth.json 失败：\(error.localizedDescription)", for: accountKey)
            }
        }

        do {
            let context = try authStore.loadSnapshotAuthContext(for: accountKey)
            let usageSnapshot = try await api.fetchUsage(with: context)
            let existingState = runtimeStates[accountKey] ?? AccountRuntimeState()
            let subscriptionSnapshot = await refreshSubscriptionIfNeeded(
                accountKey: accountKey,
                context: context,
                existingState: existingState
            )

            runtimeStates[accountKey] = AccountRuntimeState(
                isRefreshing: false,
                lastUpdatedAt: usageSnapshot.fetchedAt,
                snapshot: usageSnapshot,
                subscriptionSnapshot: subscriptionSnapshot,
                errorMessage: nil
            )

            let storedUsage = CodexStoredUsageSnapshot(accountUsageSnapshot: usageSnapshot)
            let registry = try authStore.updateStoredUsage(
                accountKey: accountKey,
                snapshot: storedUsage,
                email: usageSnapshot.email.lowercased(),
                plan: CodexPlanType(rawValue: usageSnapshot.planType.lowercased())
            )
            applyRegistry(registry)
        } catch {
            var failedState = runtimeStates[accountKey] ?? AccountRuntimeState()
            failedState.isRefreshing = false
            failedState.errorMessage = error.localizedDescription
            runtimeStates[accountKey] = failedState
        }
    }

    // MARK: - 私有方法

    /// 从磁盘重新装载当前 `registry.json`。
    /// 默认会先同步活动 `auth.json`，让 GUI 总能吃到最新官方登录态。
    private func reloadFromDisk(syncActiveAuth: Bool = true) {
        codexHomePath = (try? authStore.resolveCodexHome().path) ?? codexHomePath

        do {
            let registry: CodexRegistryDocument
            if syncActiveAuth {
                registry = try authStore.synchronizeActiveAuthIntoRegistry()
            } else {
                registry = try authStore.loadRegistry()
            }
            applyRegistry(registry)
        } catch {
            // 即便同步失败，也尽量退回纯 registry 读取，避免整个界面空白。
            do {
                applyRegistry(try authStore.loadRegistry())
            } catch {
                accounts = []
                activeAccountKey = nil
                runtimeStates = [:]
                menuBarTitle = "Codex"
            }
        }
    }

    /// 把磁盘 registry 映射到当前 UI 状态。
    /// 这里会尽量保留已拉取到的订阅缓存，避免每次 reload 都把 12 小时缓存打掉。
    private func applyRegistry(_ registry: CodexRegistryDocument) {
        activeAccountKey = registry.activeAccountKey
        let cachedSubscriptions = (try? authStore.loadSubscriptionCache().accounts) ?? [:]

        let previousRuntimeStates = runtimeStates
        let sortedAccounts = registry.accounts.sorted { lhs, rhs in
            if lhs.accountKey == registry.activeAccountKey { return true }
            if rhs.accountKey == registry.activeAccountKey { return false }
            return lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
        }

        var nextRuntimeStates: [String: AccountRuntimeState] = [:]
        for account in sortedAccounts {
            var state = previousRuntimeStates[account.accountKey] ?? AccountRuntimeState()

            if let storedSnapshot = account.lastUsage {
                let storedDate = account.lastUsageAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(timeIntervalSince1970: TimeInterval(account.createdAt))
                let shouldReplaceSnapshot = state.snapshot == nil ||
                    state.lastUpdatedAt == nil ||
                    storedDate >= (state.lastUpdatedAt ?? .distantPast)

                if shouldReplaceSnapshot {
                    state.snapshot = AccountUsageSnapshot(
                        storedSnapshot: storedSnapshot,
                        email: account.email,
                        fallbackPlan: account.resolvedPlan,
                        fetchedAt: storedDate
                    )
                    state.lastUpdatedAt = storedDate
                }
            }

            if let storedSubscription = cachedSubscriptions[account.accountKey] {
                let cachedSnapshot = AccountSubscriptionSnapshot(storedSnapshot: storedSubscription)
                let shouldReplaceSubscription = state.subscriptionSnapshot == nil ||
                    cachedSnapshot.fetchedAt >= (state.subscriptionSnapshot?.fetchedAt ?? .distantPast)

                if shouldReplaceSubscription {
                    state.subscriptionSnapshot = cachedSnapshot
                }
            } else if let subscriptionSnapshot = state.subscriptionSnapshot {
                // 兼容本次版本升级：如果用户当前运行态已经有订阅信息，但磁盘缓存还不存在，
                // 立即补写一份到 `~/.codex/accounts/subscriptions.json`，下次启动就能直接显示。
                let storedSnapshot = CodexStoredSubscriptionSnapshot(accountSubscriptionSnapshot: subscriptionSnapshot)
                _ = try? authStore.updateStoredSubscription(accountKey: account.accountKey, snapshot: storedSnapshot)
            }

            nextRuntimeStates[account.accountKey] = state
        }

        accounts = sortedAccounts
        runtimeStates = nextRuntimeStates
        rebuildMenuBarTitle()
    }

    /// 订阅信息变化频率远低于用量，因此先判断缓存是否过期。
    private func refreshSubscriptionIfNeeded(
        accountKey: String,
        context: CodexAuthContext,
        existingState: AccountRuntimeState
    ) async -> AccountSubscriptionSnapshot? {
        if let snapshot = existingState.subscriptionSnapshot,
           Date().timeIntervalSince(snapshot.fetchedAt) < subscriptionRefreshInterval {
            return snapshot
        }

        do {
            let snapshot = try await api.fetchSubscription(with: context)
            let storedSnapshot = CodexStoredSubscriptionSnapshot(accountSubscriptionSnapshot: snapshot)
            _ = try? authStore.updateStoredSubscription(accountKey: accountKey, snapshot: storedSnapshot)
            return snapshot
        } catch {
            return existingState.subscriptionSnapshot
        }
    }

    /// 启动固定周期的后台刷新循环。
    private func startRefreshLoop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = Task { [weak self] in
            guard let self else {
                return
            }

            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: automaticRefreshIntervalSeconds * 1_000_000_000)
                } catch {
                    return
                }

                await MainActor.run {
                    self.refreshAllAccounts()
                }
            }
        }
    }

    /// 设置某个账号的错误文案。
    private func setError(_ message: String, for accountKey: String?) {
        guard let accountKey else {
            return
        }

        var state = runtimeStates[accountKey] ?? AccountRuntimeState()
        state.errorMessage = message
        runtimeStates[accountKey] = state
    }

    /// 当前菜单栏标题先保持简洁稳定，避免账号数较多时标题频繁抖动。
    private func rebuildMenuBarTitle() {
        menuBarTitle = "Codex"
    }

    /// 按当前筛选条件判断账号是否应当出现在列表中。
    /// 这样筛选逻辑可以稳定复用在列表、面板高度和空状态中。
    private func shouldDisplayAccount(_ accountKey: String) -> Bool {
        guard let account = accounts.first(where: { $0.accountKey == accountKey }),
              shouldDisplayPlan(for: account) else {
            return false
        }

        switch accountVisibilityFilter {
        case .allAccounts:
            return true
        case .availableAccounts:
            return isAccountAvailable(accountKey)
        }
    }

    /// 判断账号套餐类型是否满足底部 checkbox 筛选。
    /// 三项全选代表“不过滤套餐类型”，此时未知或未来新增套餐也会继续显示。
    private func shouldDisplayPlan(for account: CodexRegistryAccount) -> Bool {
        let allPlanFilters = Set(AccountPlanFilter.allCases)
        if enabledPlanFilters == allPlanFilters {
            return true
        }

        guard let planFilter = planFilter(for: account) else {
            return false
        }

        return enabledPlanFilters.contains(planFilter)
    }

    /// 从运行时快照优先解析套餐；没有快照时退回 registry 中已有的静态套餐。
    /// 这样用户刚刷新出最新套餐后，筛选能立即跟随接口结果，而不是等下一次写盘。
    private func planFilter(for account: CodexRegistryAccount) -> AccountPlanFilter? {
        let snapshotPlan = runtimeStates[account.accountKey]?.snapshot?.planType
        let rawPlan = snapshotPlan ?? account.resolvedPlan?.badgeTitle
        let normalizedPlan = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if normalizedPlan.contains("pro") {
            return .pro
        }

        if normalizedPlan == "plus" {
            return .plus
        }

        if normalizedPlan == "free" {
            return .free
        }

        return nil
    }

    /// 后台观察 `auth.json` 是否变化。
    /// 这样菜单栏里点击一次“添加账号”即可，浏览器登录完成后会自动导入，
    /// 不再额外打开独立窗口，也不再要求用户手动点击同步。
    private func startLoginWatchLoop(baselineFingerprint: Data?, process: Process) {
        loginWatchTask?.cancel()
        isLaunchingLogin = true

        loginWatchTask = Task { [weak self] in
            guard let self else {
                return
            }

            let startedAt = Date()

            while Task.isCancelled == false,
                  Date().timeIntervalSince(startedAt) < loginWatchTimeoutSeconds {
                do {
                    try await Task.sleep(nanoseconds: loginWatchIntervalSeconds * 1_000_000_000)
                } catch {
                    break
                }

                if await completeLoginIfAuthChanged(baselineFingerprint: baselineFingerprint) {
                    break
                }

                // 如果官方登录命令已经退出，但 auth.json 没有变化，说明用户大概率取消或登录失败。
                // 此时直接结束“登录中”，让用户可以立即再次点击“添加账号”，而不是等满超时时间。
                if process.isRunning == false {
                    let didCompleteLogin = await completeLoginIfAuthChanged(baselineFingerprint: baselineFingerprint)
                    if didCompleteLogin == false, process.terminationStatus != 0 {
                        await MainActor.run {
                            if self.loginProcess === process {
                                self.loginErrorMessage = "codex login 进程异常退出，状态码：\(process.terminationStatus)。请确认 Codex App 或 Codex CLI 可以正常执行。"
                                NSLog("CodexMonitor: 登录流程失败，auth.json 未变化，codex login 状态码：%d。", process.terminationStatus)
                            }
                        }
                    }
                    break
                }
            }

            await MainActor.run {
                if self.loginProcess === process {
                    self.loginProcess = nil
                }
                self.isLaunchingLogin = false
                self.loginWatchTask = nil
            }
        }
    }

    /// 检查官方登录是否已经把新认证结果写入 `auth.json`。
    /// 返回 `true` 表示登录结果已经成功同步进账号列表，监视任务可以结束。
    private func completeLoginIfAuthChanged(baselineFingerprint: Data?) async -> Bool {
        do {
            let latestFingerprint = try authStore.activeAuthFingerprint()
            guard latestFingerprint != baselineFingerprint else {
                return false
            }

            let registry = try authStore.synchronizeActiveAuthIntoRegistry()
            applyRegistry(registry)
            await refreshActiveAccountNamesIfNeeded()
            NSLog("CodexMonitor: 检测到 auth.json 已更新，已同步新登录结果。")

            if let activeAccountKey {
                await refreshAccount(activeAccountKey)
            }

            return true
        } catch {
            // 登录过程中 `auth.json` 可能短暂处于未写完状态。
            // 这里不把它当作失败弹给用户，下一轮监视会继续尝试。
            return false
        }
    }

    /// 尝试按 `codex-auth` 的团队工作区命名规则补齐账号名称。
    /// 这里只针对“同一 chatgpt_user_id 下存在多个账号，且至少一个 Team 账号缺少名称”的场景发请求，
    /// 避免把 `accounts/check` 变成每次刷新都无脑调用的高频接口。
    private func refreshActiveAccountNamesIfNeeded() async {
        let currentAccounts = accounts
        guard let activeAccountKey else {
            return
        }

        guard let activeAccount = currentAccounts.first(where: { $0.accountKey == activeAccountKey }) else {
            return
        }

        guard shouldRefreshTeamAccountNames(
            for: activeAccount.chatgptUserID,
            accounts: currentAccounts
        ) else {
            return
        }

        do {
            guard let context = try authStore.loadActiveAuthContext() else {
                return
            }

            let entries = try await api.fetchAccountNames(with: context)
            guard entries.isEmpty == false else {
                return
            }

            let updatedRegistry = try applyAccountNameEntries(
                entries,
                for: activeAccount.chatgptUserID
            )
            applyRegistry(updatedRegistry)
        } catch {
            // 账号名称补全属于增强体验，不应该打断主流程。
            // 因此这里只静默吞掉错误，保留当前已可用的登录、切换、用量刷新能力。
        }
    }

    /// 判断某个用户作用域下是否需要刷新 Team 工作区名称。
    /// 规则和 `codex-auth` 保持一致：
    /// 1. 同一 `chatgpt_user_id` 下账号数必须大于 1
    /// 2. 至少存在一个 Team 账号
    /// 3. 至少存在一个 Team 账号还没有 `account_name`
    private func shouldRefreshTeamAccountNames(
        for userID: String,
        accounts: [CodexRegistryAccount]
    ) -> Bool {
        let scopedAccounts = accounts.filter { $0.chatgptUserID == userID }
        guard scopedAccounts.count > 1 else {
            return false
        }

        let teamAccounts = scopedAccounts.filter { $0.resolvedPlan == .team }
        guard teamAccounts.isEmpty == false else {
            return false
        }

        return teamAccounts.contains { account in
            let accountName = account.accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return accountName.isEmpty
        }
    }

    /// 把 `accounts/check` 返回的账号名称回写到 registry。
    /// 行为尽量对齐参考实现：
    /// - 命中的账号用最新名称覆盖
    /// - 同作用域内 Team 账号如果这次没有返回名称，则清空旧名称
    /// - 非 Team 且原本就没有名称的账号，不做无意义覆盖
    private func applyAccountNameEntries(
        _ entries: [CodexAccountNameEntry],
        for userID: String
    ) throws -> CodexRegistryDocument {
        var registry = try authStore.loadRegistry()
        var changed = false

        for index in registry.accounts.indices {
            guard registry.accounts[index].chatgptUserID == userID else {
                continue
            }

            let matchedEntry = entries.first { entry in
                entry.accountID == registry.accounts[index].chatgptAccountID
            }

            let existingName = registry.accounts[index].accountName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isTeamAccount = registry.accounts[index].resolvedPlan == .team

            if matchedEntry == nil, isTeamAccount == false, (existingName?.isEmpty ?? true) {
                continue
            }

            let nextName = matchedEntry?.accountName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedNextName = nextName?.isEmpty == false ? nextName : nil

            if existingName != normalizedNextName {
                registry.accounts[index].accountName = normalizedNextName
                changed = true
            }
        }

        guard changed else {
            return registry
        }

        try authStore.saveRegistry(registry)
        return registry
    }
}
