//
//  CodexAuthStore.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/17.
//

import Darwin
import Foundation

/// 与 `codex-auth` 完全对齐的本地存储服务。
/// 该服务只负责三件事情：
/// 1. 解析 `~/.codex` 根目录与 accounts 子目录结构
/// 2. 读写 `registry.json`、`auth.json`、`accounts/*.auth.json`
/// 3. 提供登录导入、账号切换、账号删除这些围绕磁盘状态的原子操作
final class CodexAuthStore {

    /// 统一使用文件管理器处理磁盘读写，便于后续做单元测试替身。
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// `codex-auth` 的根目录解析顺序：
    /// 1. 非空且已存在的 `CODEX_HOME`
    /// 2. 当前真实登录用户主目录下的 `.codex`
    /// 3. `USERPROFILE/.codex`
    func resolveCodexHome() throws -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           overridePath.isEmpty == false {
            let overrideURL = URL(fileURLWithPath: overridePath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: overrideURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CodexAuthStoreError.invalidCodexHome("CODEX_HOME 指向的目录不存在或不是文件夹：\(overrideURL.path)")
            }
            return overrideURL.standardizedFileURL
        }

        // App Sandbox 会把 `HOME` 和 `homeDirectoryForCurrentUser` 重定向到容器目录。
        // 为了真正复用 Codex CLI / Codex App 的账号数据，这里必须强制解析真实用户主目录。
        if let realHomeDirectory = resolveRealUserHomeDirectory() {
            return realHomeDirectory.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL
        }

        if let userProfile = ProcessInfo.processInfo.environment["USERPROFILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           userProfile.isEmpty == false {
            return URL(fileURLWithPath: userProfile).appendingPathComponent(".codex", isDirectory: true).standardizedFileURL
        }

        throw CodexAuthStoreError.invalidCodexHome("无法解析 Codex 根目录。")
    }

    /// 解析当前真实登录用户主目录。
    /// 优先使用 `getpwuid(getuid())`，这样不会被沙盒容器路径干扰。
    private func resolveRealUserHomeDirectory() -> URL? {
        guard let passwdPointer = getpwuid(getuid()),
              let directoryPointer = passwdPointer.pointee.pw_dir else {
            return nil
        }

        let directoryPath = String(cString: directoryPointer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard directoryPath.isEmpty == false else {
            return nil
        }

        return URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    /// `~/.codex/accounts`
    func accountsDirectoryURL() throws -> URL {
        try resolveCodexHome().appendingPathComponent("accounts", isDirectory: true)
    }

    /// 当前活动账号的标准 `auth.json`
    func activeAuthURL() throws -> URL {
        try resolveCodexHome().appendingPathComponent("auth.json", isDirectory: false)
    }

    /// `accounts/registry.json`
    func registryURL() throws -> URL {
        try accountsDirectoryURL().appendingPathComponent("registry.json", isDirectory: false)
    }

    /// `accounts/subscriptions.json`
    /// 这个文件是 GUI 自己的轻量缓存，用于启动时立即恢复订阅到期时间和年度标签。
    func subscriptionCacheURL() throws -> URL {
        try accountsDirectoryURL().appendingPathComponent("subscriptions.json", isDirectory: false)
    }

    /// 读取 `registry.json`。
    /// 如果文件不存在，则返回一个空 registry，和参考实现“首次使用时可自动导入当前 auth”保持一致。
    func loadRegistry() throws -> CodexRegistryDocument {
        let registryURL = try registryURL()
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: registryURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CodexRegistryDocument.self, from: data)
    }

    /// 写回 `registry.json`。
    /// 写入前会保留一份变更前备份，格式与 `codex-auth` 的 `registry.json.bak.<timestamp>` 保持一致。
    func saveRegistry(_ document: CodexRegistryDocument) throws {
        try ensureAccountsDirectory()

        let registryURL = try registryURL()
        var normalized = document
        normalized.schemaVersion = CodexRegistrySchema.currentVersion

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalized)

        try backupIfNeeded(currentFileURL: registryURL, newContents: data, backupBaseName: "registry.json")
        try data.write(to: registryURL, options: .atomic)
    }

    /// 读取 GUI 订阅缓存。
    /// 如果文件不存在，直接返回空缓存；这样首次启动或用户只使用 `codex-auth` CLI 时不会报错。
    func loadSubscriptionCache() throws -> CodexSubscriptionCacheDocument {
        let cacheURL = try subscriptionCacheURL()
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: cacheURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CodexSubscriptionCacheDocument.self, from: data)
    }

    /// 写回 GUI 订阅缓存。
    /// 写入前同样做备份，避免一次异常写入把历史订阅到期信息全部覆盖。
    func saveSubscriptionCache(_ document: CodexSubscriptionCacheDocument) throws {
        try ensureAccountsDirectory()

        let cacheURL = try subscriptionCacheURL()
        var normalized = document
        normalized.schemaVersion = 1

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalized)

        try backupIfNeeded(currentFileURL: cacheURL, newContents: data, backupBaseName: "subscriptions.json")
        try data.write(to: cacheURL, options: .atomic)
    }

    /// 更新单个账号的订阅缓存。
    /// 订阅接口 12 小时刷新一次，成功后立刻落盘，保证下次启动时不用等网络请求即可展示。
    @discardableResult
    func updateStoredSubscription(
        accountKey: String,
        snapshot: CodexStoredSubscriptionSnapshot
    ) throws -> CodexSubscriptionCacheDocument {
        var cache = try loadSubscriptionCache()
        cache.accounts[accountKey] = snapshot
        try saveSubscriptionCache(cache)
        return cache
    }

    /// 删除账号时同步移除 GUI 订阅缓存。
    /// 这里不影响 `registry.json` 删除主流程；缓存缺失或已删除时直接返回。
    func removeStoredSubscription(accountKey: String) throws {
        var cache = try loadSubscriptionCache()
        guard cache.accounts.removeValue(forKey: accountKey) != nil else {
            return
        }

        try saveSubscriptionCache(cache)
    }

    /// 读取某个账号对应的 `accounts/*.auth.json`。
    func loadAuthDocument(for accountKey: String) throws -> CodexStoredAuthDocument {
        let authURL = try accountSnapshotURL(for: accountKey)
        let data = try Data(contentsOf: authURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CodexStoredAuthDocument.self, from: data)
    }

    /// 从活动 `auth.json` 中解析可用的 GUI 认证上下文。
    /// 这里只接受 ChatGPT Web 模式；API Key 模式虽然也会被识别出来，但目前不参与用量页面展示。
    func loadActiveAuthContext() throws -> CodexAuthContext? {
        let url = try activeAuthURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try decodeAuthContext(from: url)
    }

    /// 从账号快照中解析认证上下文。
    func loadSnapshotAuthContext(for accountKey: String) throws -> CodexAuthContext {
        try decodeAuthContext(from: accountSnapshotURL(for: accountKey))
    }

    /// 读取当前活动 `auth.json` 的内容指纹。
    /// 登录按钮触发官方 `codex login` 后，GUI 会在后台对比这个指纹，
    /// 一旦文件内容发生变化，就自动同步新账号，不再要求用户手动点“同步”。
    func activeAuthFingerprint() throws -> Data? {
        let url = try activeAuthURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    /// 在后台启动 `codex login` 或 `codex login --device-auth`。
    /// GUI 不直接自己跑 OAuth，而是复用官方登录命令，把产物继续写回同一份 `~/.codex/auth.json`。
    ///
    /// 这里刻意不再通过 AppleScript 打开 Terminal：
    /// 1. 用户只需要看到浏览器登录页，不应该被额外弹出的终端窗口打断。
    /// 2. 返回 `Process` 句柄给 `AppState`，这样菜单栏可以提供“取消登录”，避免失败登录一直卡在登录中。
    /// 3. 使用 login shell + 常见 Homebrew 路径，尽量复用用户本机已经安装好的 `codex` 命令。
    func startCodexLoginProcess(
        deviceAuth: Bool,
        onLoginURL: @escaping (URL) -> Void
    ) throws -> Process {
        let codexHome = try resolveCodexHome()
        let realHome = resolveRealUserHomeDirectory() ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        try ensureCodexHomeExists()

        let codexExecutableURL = try resolveCodexExecutableURL(realHome: realHome)
        let process = Process()
        process.executableURL = codexExecutableURL
        process.arguments = deviceAuth ? ["login", "--device-auth"] : ["login"]

        // 菜单栏 App 由 launchd 启动时拿不到用户终端里的完整环境变量。
        // 这里显式补齐 HOME、CODEX_HOME 和常见 CLI 路径，保证官方 Codex CLI 读写真实用户目录，
        // 同时保留用户原有 PATH，避免影响通过包管理器安装的自定义 codex 可执行文件。
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = realHome.path
        environment["CODEX_HOME"] = codexHome.path
        environment["PATH"] = codexLoginSearchPath(realHome: realHome, inheritedPath: environment["PATH"])
        process.environment = environment

        // 后台进程没有用户可见终端，标准输入直接接到空设备，避免命令意外等待键盘输入。
        process.standardInput = FileHandle.nullDevice

        // `codex login` 通常会自己打开浏览器。这里持续读取管道避免阻塞，
        // 但只有当 CLI 明确报告“浏览器打开失败”时，才把登录 URL 交给 App 兜底打开。
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let loginURLScanner = CodexLoginFallbackURLScanner()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            if let url = loginURLScanner.append(handle.availableData) {
                onLoginURL(url)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            if let url = loginURLScanner.append(handle.availableData) {
                onLoginURL(url)
            }
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        process.terminationHandler = { process in
            // 进程退出后清理回调，避免 FileHandle 持续持有闭包。
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil

            if process.terminationStatus == 0 {
                NSLog("CodexMonitor: codex login 进程正常退出。")
            } else {
                NSLog("CodexMonitor: codex login 进程异常退出，状态码：%d。", process.terminationStatus)
            }
        }

        NSLog("CodexMonitor: 启动 codex login，CLI 路径：%@，CODEX_HOME：%@", codexExecutableURL.path, codexHome.path)
        try process.run()
        return process
    }

    /// 把当前活动 `auth.json` 同步进 `accounts/registry.json` 与 `accounts/*.auth.json`。
    /// 这一步是 GUI 版最关键的兼容层：
    /// 用户在 Codex CLI / Codex App 里完成登录或 token 刷新后，GUI 只需要重新同步即可。
    @discardableResult
    func synchronizeActiveAuthIntoRegistry() throws -> CodexRegistryDocument {
        try ensureAccountsDirectory()

        guard let context = try loadActiveAuthContext() else {
            return try loadRegistry()
        }

        var registry = try loadRegistry()
        let nowSeconds = Int64(Date().timeIntervalSince1970)
        let nowMilliseconds = Int64(Date().timeIntervalSince1970 * 1000)

        if let index = registry.accounts.firstIndex(where: { $0.accountKey == context.recordKey }) {
            registry.accounts[index].email = context.email
            registry.accounts[index].chatgptAccountID = context.chatgptAccountID
            registry.accounts[index].chatgptUserID = context.chatgptUserID
            registry.accounts[index].plan = context.plan
            registry.accounts[index].authMode = context.authMode
            registry.accounts[index].lastUsedAt = nowSeconds
        } else {
            registry.accounts.append(
                CodexRegistryAccount(
                    accountKey: context.recordKey,
                    chatgptAccountID: context.chatgptAccountID,
                    chatgptUserID: context.chatgptUserID,
                    email: context.email,
                    alias: "",
                    accountName: nil,
                    plan: context.plan,
                    authMode: context.authMode,
                    createdAt: nowSeconds,
                    lastUsedAt: nowSeconds,
                    lastUsage: nil,
                    lastUsageAt: nil,
                    lastLocalRollout: nil
                )
            )
        }

        let previouslyActiveKey = registry.activeAccountKey
        registry.activeAccountKey = context.recordKey
        if previouslyActiveKey != context.recordKey || registry.activeAccountActivatedAtMs == nil {
            registry.activeAccountActivatedAtMs = nowMilliseconds
        }

        let snapshotURL = try accountSnapshotURL(for: context.recordKey)
        try copyFileIfDifferent(from: activeAuthURL(), to: snapshotURL)
        try saveRegistry(registry)
        return registry
    }

    /// 切换账号的本质就是：
    /// 1. 把目标快照覆写回 `~/.codex/auth.json`
    /// 2. 把 `registry.active_account_key` 指向对应账号
    /// 3. 更新激活时间，方便本地 rollout 归因
    func switchToAccount(accountKey: String) throws {
        var registry = try loadRegistry()
        guard registry.accounts.contains(where: { $0.accountKey == accountKey }) else {
            throw CodexAuthStoreError.missingAccount("没有找到待切换账号：\(accountKey)")
        }

        let snapshotURL = try accountSnapshotURL(for: accountKey)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            throw CodexAuthStoreError.missingAccount("账号快照文件不存在：\(snapshotURL.lastPathComponent)")
        }

        let activeURL = try activeAuthURL()
        try ensureCodexHomeExists()
        try backupAuthIfNeeded(newAuthFileURL: snapshotURL)
        try copyFileIfDifferent(from: snapshotURL, to: activeURL, forceWhenDestinationMissing: true)

        registry.activeAccountKey = accountKey
        registry.activeAccountActivatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let index = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) {
            registry.accounts[index].lastUsedAt = Int64(Date().timeIntervalSince1970)
        }

        try saveRegistry(registry)
    }

    /// 删除账号时同步删除 `registry` 条目和当前快照文件。
    /// 如果删掉的是活动账号，则自动把下一条账号提升为活动账号，尽量保持 `~/.codex/auth.json` 仍然可用。
    func deleteAccount(accountKey: String) throws {
        var registry = try loadRegistry()
        guard let removedIndex = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) else {
            return
        }

        let removingActiveAccount = registry.activeAccountKey == accountKey
        registry.accounts.remove(at: removedIndex)

        let snapshotURL = try accountSnapshotURL(for: accountKey)
        if fileManager.fileExists(atPath: snapshotURL.path) {
            try fileManager.removeItem(at: snapshotURL)
        }

        if removingActiveAccount {
            if let replacement = registry.accounts.first {
                registry.activeAccountKey = replacement.accountKey
                registry.activeAccountActivatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
                try switchSnapshotIntoActiveAuth(accountKey: replacement.accountKey)
            } else {
                registry.activeAccountKey = nil
                registry.activeAccountActivatedAtMs = nil

                let activeURL = try activeAuthURL()
                if fileManager.fileExists(atPath: activeURL.path) {
                    try fileManager.removeItem(at: activeURL)
                }
            }
        }

        try saveRegistry(registry)
        try? removeStoredSubscription(accountKey: accountKey)
    }

    /// 将最新用量回写到 `registry.json`。
    /// 这样 GUI 重启后仍然能立刻显示最近一次成功拉取的用量，而不是一片空白。
    func updateStoredUsage(
        accountKey: String,
        snapshot: CodexStoredUsageSnapshot,
        email: String,
        plan: CodexPlanType?
    ) throws -> CodexRegistryDocument {
        var registry = try loadRegistry()
        guard let index = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) else {
            throw CodexAuthStoreError.missingAccount("没有找到待更新用量的账号：\(accountKey)")
        }

        registry.accounts[index].email = email
        registry.accounts[index].plan = plan ?? registry.accounts[index].plan
        registry.accounts[index].lastUsage = snapshot
        registry.accounts[index].lastUsageAt = Int64(Date().timeIntervalSince1970)

        try saveRegistry(registry)
        return registry
    }

    /// 解析 `record_key` 对应的快照路径。
    /// `codex-auth` 对包含 `:` 等文件名不安全字符的 key 使用 base64url 无填充编码。
    func accountSnapshotURL(for accountKey: String) throws -> URL {
        let filenameSafeKey = accountFileKey(for: accountKey)
        return try accountsDirectoryURL().appendingPathComponent("\(filenameSafeKey).auth.json", isDirectory: false)
    }

    // MARK: - 私有辅助方法

    /// 确保 `~/.codex/accounts` 目录存在。
    private func ensureAccountsDirectory() throws {
        let accountsURL = try accountsDirectoryURL()
        try fileManager.createDirectory(at: accountsURL, withIntermediateDirectories: true)
    }

    /// 确保 `~/.codex` 根目录存在。
    private func ensureCodexHomeExists() throws {
        let codexHome = try resolveCodexHome()
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
    }

    /// 解析可用的官方 Codex CLI。
    /// 之前只依赖 shell 脚本在 Homebrew / npm / cargo 等路径中查找 `codex`，但菜单栏 App 的运行环境
    /// 往往没有用户终端里的 PATH；如果用户只安装了官方 Codex.app，真实 CLI 会位于 App bundle 内部，
    /// 这时点击“添加账号”会启动一个立即退出的后台进程，界面上就表现为没有响应。
    /// 因此这里在 Swift 层提前解析并校验可执行文件，找不到时直接抛出可展示的错误。
    private func resolveCodexExecutableURL(realHome: URL) throws -> URL {
        let searchPath = codexLoginSearchPath(realHome: realHome, inheritedPath: ProcessInfo.processInfo.environment["PATH"])
        let bundledCandidatePaths = [
            "\(realHome.path)/.npm-global/bin/codex",
            "\(realHome.path)/.local/bin/codex",
            "\(realHome.path)/.bun/bin/codex",
            "\(realHome.path)/.cargo/bin/codex",
            "\(realHome.path)/.volta/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        for candidatePath in bundledCandidatePaths {
            if isExecutableFile(atPath: candidatePath) {
                return URL(fileURLWithPath: candidatePath, isDirectory: false)
            }
        }

        if let pathCandidate = findExecutable(named: "codex", inSearchPath: searchPath) {
            return pathCandidate
        }

        throw CodexAuthStoreError.missingCodexCLI("未找到可用的 codex 命令。请确认已安装官方 Codex App 或 Codex CLI。")
    }

    /// 生成登录子进程使用的 PATH。
    /// 这个方法集中维护常见安装路径，避免启动命令、查找命令和后续排障日志各自拼一份路径导致不一致。
    private func codexLoginSearchPath(realHome: URL, inheritedPath: String?) -> String {
        let preferredPaths = [
            "\(realHome.path)/.npm-global/bin",
            "\(realHome.path)/.local/bin",
            "\(realHome.path)/.bun/bin",
            "\(realHome.path)/.cargo/bin",
            "\(realHome.path)/.volta/bin",
            "/Applications/Codex.app/Contents/Resources",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let inheritedPaths = inheritedPath?
            .split(separator: ":")
            .map(String.init) ?? []

        var seenPaths = Set<String>()
        return (preferredPaths + inheritedPaths)
            .filter { path in
                let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalized.isEmpty == false, seenPaths.contains(normalized) == false else {
                    return false
                }
                seenPaths.insert(normalized)
                return true
            }
            .joined(separator: ":")
    }

    /// 在给定 PATH 中查找可执行文件。
    /// 不通过 shell 的原因是菜单栏 App 内执行 login shell 的行为依赖用户配置文件，失败时也不容易把错误同步回 UI。
    private func findExecutable(named executableName: String, inSearchPath searchPath: String) -> URL? {
        for directoryPath in searchPath.split(separator: ":").map(String.init) {
            let candidatePath = URL(fileURLWithPath: directoryPath, isDirectory: true)
                .appendingPathComponent(executableName, isDirectory: false)
                .path
            if isExecutableFile(atPath: candidatePath) {
                return URL(fileURLWithPath: candidatePath, isDirectory: false)
            }
        }

        return nil
    }

    /// 判断路径是否是普通可执行文件，排除同名目录等异常情况。
    private func isExecutableFile(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue == false else {
            return false
        }

        return fileManager.isExecutableFile(atPath: path)
    }

    /// 直接把某个快照切到当前 `auth.json`。
    /// 这一步用于删除活动账号后自动补位，不额外改 registry 逻辑。
    private func switchSnapshotIntoActiveAuth(accountKey: String) throws {
        let snapshotURL = try accountSnapshotURL(for: accountKey)
        let activeURL = try activeAuthURL()
        try backupAuthIfNeeded(newAuthFileURL: snapshotURL)
        try copyFileIfDifferent(from: snapshotURL, to: activeURL, forceWhenDestinationMissing: true)
    }

    /// 如果旧 `auth.json` 和目标内容不同，则先备份旧文件。
    private func backupAuthIfNeeded(newAuthFileURL: URL) throws {
        let activeURL = try activeAuthURL()
        guard fileManager.fileExists(atPath: activeURL.path) else {
            return
        }

        let newContents = try Data(contentsOf: newAuthFileURL)
        try backupIfNeeded(currentFileURL: activeURL, newContents: newContents, backupBaseName: "auth.json")
    }

    /// 内容有变化时创建备份，文件名格式严格保持 `*.bak.YYYYMMDD-hhmmss[.N]`。
    private func backupIfNeeded(currentFileURL: URL, newContents: Data, backupBaseName: String) throws {
        guard fileManager.fileExists(atPath: currentFileURL.path) else {
            return
        }

        let currentContents = try Data(contentsOf: currentFileURL)
        guard currentContents != newContents else {
            return
        }

        try ensureAccountsDirectory()
        let backupURL = try makeBackupURL(baseName: backupBaseName)
        try fileManager.copyItem(at: currentFileURL, to: backupURL)
        try pruneBackups(baseName: backupBaseName, maxCount: 5)
    }

    /// 生成唯一备份文件名，避免同一秒内多次写入互相覆盖。
    private func makeBackupURL(baseName: String) throws -> URL {
        let directoryURL = try accountsDirectoryURL()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let baseFileName = "\(baseName).bak.\(formatter.string(from: Date()))"
        var attempt = 0

        while true {
            let candidateName = attempt == 0 ? baseFileName : "\(baseFileName).\(attempt)"
            let candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: false)
            if fileManager.fileExists(atPath: candidateURL.path) == false {
                return candidateURL
            }
            attempt += 1
        }
    }

    /// 备份文件最多保留 5 个，和参考实现一致。
    private func pruneBackups(baseName: String, maxCount: Int) throws {
        let directoryURL = try accountsDirectoryURL()
        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let backups = entries
            .filter { $0.lastPathComponent.hasPrefix("\(baseName).bak.") }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

        guard backups.count > maxCount else {
            return
        }

        for staleURL in backups.dropFirst(maxCount) {
            try? fileManager.removeItem(at: staleURL)
        }
    }

    /// 在必要时复制文件，避免无意义地触发备份链路和文件监控。
    private func copyFileIfDifferent(from sourceURL: URL, to destinationURL: URL, forceWhenDestinationMissing: Bool = false) throws {
        let sourceData = try Data(contentsOf: sourceURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            let destinationData = try Data(contentsOf: destinationURL)
            guard sourceData != destinationData else {
                return
            }
            try fileManager.removeItem(at: destinationURL)
        } else if forceWhenDestinationMissing == false {
            // 目标不存在时直接继续创建；这里保留分支只是为了让调用语义更清晰。
        }

        try ensureParentDirectory(of: destinationURL)
        try sourceData.write(to: destinationURL, options: .atomic)
    }

    /// 解析 `auth.json` 的核心认证上下文。
    /// 逻辑严格参考 `codex-auth/src/auth.zig`：
    /// - 读取 `tokens.account_id`
    /// - 校验 JWT 里的 `chatgpt_account_id`
    /// - 使用 `chatgpt_user_id + "::" + chatgpt_account_id` 作为 record key
    private func decodeAuthContext(from fileURL: URL) throws -> CodexAuthContext {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let document = try decoder.decode(CodexStoredAuthDocument.self, from: data)

        if let apiKey = document.openAIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), apiKey.isEmpty == false {
            throw CodexAuthStoreError.unsupportedAuthMode("当前 auth.json 是 API Key 模式，暂不支持接入 GUI 用量面板。")
        }

        guard let tokens = document.tokens else {
            throw CodexAuthStoreError.invalidAuthFile("auth.json 缺少 tokens 字段。")
        }

        guard let idToken = tokens.idToken?.trimmingCharacters(in: .whitespacesAndNewlines), idToken.isEmpty == false else {
            throw CodexAuthStoreError.invalidAuthFile("auth.json 缺少 id_token。")
        }

        guard let accessToken = tokens.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), accessToken.isEmpty == false else {
            throw CodexAuthStoreError.invalidAuthFile("auth.json 缺少 access_token。")
        }

        guard let tokenAccountID = tokens.accountID?.trimmingCharacters(in: .whitespacesAndNewlines), tokenAccountID.isEmpty == false else {
            throw CodexAuthStoreError.invalidAuthFile("auth.json 缺少 account_id。")
        }

        let payload = try decodeJWTPayload(idToken)
        let email = (payload["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard email.isEmpty == false else {
            throw CodexAuthStoreError.invalidAuthFile("auth.json 的 JWT 缺少 email。")
        }

        guard let authObject = payload["https://api.openai.com/auth"] as? [String: Any] else {
            throw CodexAuthStoreError.invalidAuthFile("auth.json 的 JWT 缺少 OpenAI auth claims。")
        }

        guard let jwtAccountID = (authObject["chatgpt_account_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), jwtAccountID.isEmpty == false else {
            throw CodexAuthStoreError.invalidAuthFile("JWT 缺少 chatgpt_account_id。")
        }

        guard jwtAccountID == tokenAccountID else {
            throw CodexAuthStoreError.invalidAuthFile("auth.json 的 account_id 与 JWT 内的 chatgpt_account_id 不一致。")
        }

        let userID = ((authObject["chatgpt_user_id"] as? String) ?? (authObject["user_id"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard userID.isEmpty == false else {
            throw CodexAuthStoreError.invalidAuthFile("JWT 缺少 chatgpt_user_id。")
        }

        let plan = (authObject["chatgpt_plan_type"] as? String).flatMap(CodexPlanType.init(rawValue:))
        let recordKey = "\(userID)::\(tokenAccountID)"

        return CodexAuthContext(
            email: email,
            chatgptAccountID: tokenAccountID,
            chatgptUserID: userID,
            recordKey: recordKey,
            accessToken: accessToken,
            refreshToken: tokens.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            lastRefresh: document.lastRefresh?.trimmingCharacters(in: .whitespacesAndNewlines),
            plan: plan,
            authMode: .chatgpt
        )
    }

    /// JWT payload 解码。
    private func decodeJWTPayload(_ jwt: String) throws -> [String: Any] {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else {
            throw CodexAuthStoreError.invalidAuthFile("JWT 结构不合法。")
        }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else {
            throw CodexAuthStoreError.invalidAuthFile("JWT payload 不是合法 Base64。")
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw CodexAuthStoreError.invalidAuthFile("JWT payload 不是合法 JSON 对象。")
        }

        return payload
    }

    /// `codex-auth` 的快照文件名规则：
    /// 如果 key 含有文件名不安全字符，就转成 base64url 无填充编码。
    /// `record_key` 自带 `::`，因此正常情况下都会走编码路径。
    private func accountFileKey(for accountKey: String) -> String {
        guard keyNeedsFilenameEncoding(accountKey) else {
            return accountKey
        }

        let data = Data(accountKey.utf8)
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 判断一个 key 是否可以直接当成文件名。
    private func keyNeedsFilenameEncoding(_ key: String) -> Bool {
        guard key.isEmpty == false, key != ".", key != ".." else {
            return true
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return key.unicodeScalars.contains { allowed.contains($0) == false }
    }

    /// 保障父目录已创建。
    private func ensureParentDirectory(of url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    /// Shell 单引号转义。
    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

}

private final class CodexLoginFallbackURLScanner {
    private let lock = NSLock()
    private var buffer = ""
    private var didFindURL = false

    func append(_ data: Data) -> URL? {
        guard data.isEmpty == false,
              let text = String(data: data, encoding: .utf8),
              text.isEmpty == false else {
            return nil
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        guard didFindURL == false else {
            return nil
        }

        buffer += text
        if buffer.count > 8_000 {
            buffer = String(buffer.suffix(8_000))
        }

        guard Self.containsBrowserOpenFailure(in: buffer),
              let url = Self.extractFirstExternalLoginURL(from: buffer) else {
            return nil
        }

        didFindURL = true
        return url
    }

    private static func extractFirstExternalLoginURL(from text: String) -> URL? {
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: fullRange)
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:)]}")

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else {
                continue
            }

            let rawURL = String(text[matchRange])
                .trimmingCharacters(in: trailingPunctuation)
            guard let url = URL(string: rawURL),
                  isExternalLoginURL(url) else {
                continue
            }

            return url
        }

        return nil
    }

    private static func containsBrowserOpenFailure(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("failed to open browser")
            || normalized.contains("failed to open login url")
            || normalized.contains("failed to open browser for login url")
    }

    private static func isExternalLoginURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }

        if host == "localhost" ||
            host == "127.0.0.1" ||
            host == "::1" ||
            host.hasSuffix(".localhost") {
            return false
        }

        return host == "auth.openai.com" ||
            host.hasSuffix(".auth.openai.com") ||
            host == "chatgpt.com" ||
            host.hasSuffix(".chatgpt.com") ||
            host == "openai.com" ||
            host.hasSuffix(".openai.com")
    }
}

enum CodexAuthStoreError: LocalizedError {
    case invalidCodexHome(String)
    case invalidAuthFile(String)
    case missingAccount(String)
    case missingCodexCLI(String)
    case unsupportedAuthMode(String)

    var errorDescription: String? {
        switch self {
        case .invalidCodexHome(let message),
             .invalidAuthFile(let message),
             .missingAccount(let message),
             .missingCodexCLI(let message),
             .unsupportedAuthMode(let message):
            return message
        }
    }
}
