//
//  CodexUsage.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import Foundation

/// 接口返回的顶层结构，只保留当前页面展示需要的关键字段。
struct CodexUsageResponse: Decodable {
    let email: String?
    let planType: String?
    let rateLimit: CodexRateLimit?

    enum CodingKeys: String, CodingKey {
        case email
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

/// 订阅接口返回的关键字段。
/// 当前界面只关心套餐类型、到期时间和是否自动续费，因此仅保留最小必要信息。
struct CodexSubscriptionResponse: Decodable {
    let id: String?
    let planType: String?
    let activeUntil: String?
    let billingPeriod: String?
    let willRenew: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case planType = "plan_type"
        case activeUntil = "active_until"
        case billingPeriod = "billing_period"
        case willRenew = "will_renew"
    }
}

/// 用量限制信息。
struct CodexRateLimit: Decodable {
    let allowed: Bool
    let limitReached: Bool
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

/// 单个时间窗口的用量信息。
struct CodexRateLimitWindow: Decodable, Equatable {
    let usedPercent: Int
    let limitWindowSeconds: Int
    let resetAfterSeconds: Int
    let resetAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    /// 接口返回的是“已使用百分比”，而界面更适合强调“剩余百分比”。
    var remainingPercent: Int {
        max(0, 100 - usedPercent)
    }

    /// 把 Unix 时间戳转换为本地 Date，便于界面统一格式化。
    var resetDate: Date {
        Date(timeIntervalSince1970: resetAt)
    }
}

/// 适配 SwiftUI 展示的视图模型。
/// 把接口字段转换为直接可展示的数据，避免视图层散落各种业务计算。
struct UsageWindowPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let remainingPercent: Int
    let usedPercent: Int
    let resetDate: Date
}

/// 某个账号的一次成功拉取结果。
struct AccountUsageSnapshot: Equatable {
    let email: String
    let planType: String
    let allowed: Bool
    let limitReached: Bool
    let fetchedAt: Date
    let windows: [UsageWindowPresentation]

    /// 菜单栏摘要使用“最紧张的窗口剩余额度”作为数字，更贴近切换账号的使用场景。
    var summaryRemainingPercent: Int {
        windows.map(\.remainingPercent).min() ?? 0
    }
}

/// 某个账号的一次成功订阅拉取结果。
/// 订阅信息变化频率远低于用量，因此会单独缓存，并按更长周期刷新。
struct AccountSubscriptionSnapshot: Equatable {
    let planType: String
    let activeUntil: Date?
    let billingPeriod: String
    let willRenew: Bool
    let fetchedAt: Date
}

/// 订阅缓存文件的顶层结构。
/// 文件保存在 `~/.codex/accounts/subscriptions.json`，不写入 `registry.json`，
/// 这样 GUI 可以启动即恢复到期时间和年度标签，同时不会破坏 `codex-auth` 的 registry 兼容性。
struct CodexSubscriptionCacheDocument: Codable, Equatable {
    var schemaVersion: Int
    var accounts: [String: CodexStoredSubscriptionSnapshot]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case accounts
    }

    static let empty = CodexSubscriptionCacheDocument(
        schemaVersion: 1,
        accounts: [:]
    )
}

/// 单账号订阅缓存。
/// 日期统一落成 Unix 秒，避免 JSONEncoder 的 Date 策略变化导致文件格式不稳定。
struct CodexStoredSubscriptionSnapshot: Codable, Equatable {
    var planType: String
    var activeUntil: Int64?
    var billingPeriod: String
    var willRenew: Bool
    var fetchedAt: Int64

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case activeUntil = "active_until"
        case billingPeriod = "billing_period"
        case willRenew = "will_renew"
        case fetchedAt = "fetched_at"
    }
}

/// 账号运行时状态。
/// 这部分不需要持久化，只用于驱动 UI。
struct AccountRuntimeState: Equatable {
    var isRefreshing: Bool = false
    var lastUpdatedAt: Date?
    var snapshot: AccountUsageSnapshot?
    var subscriptionSnapshot: AccountSubscriptionSnapshot?
    var errorMessage: String?
}

extension AccountUsageSnapshot {
    /// 判断当前账号是否仍然可用于继续消费额度。
    /// 规则遵循产品定义：
    /// 1. 只要任意一个已知窗口剩余额度为 0，就视为不可用
    /// 2. 如果接口没有返回窗口，但顶层标记已经明确不允许继续使用，也视为不可用
    /// 3. 只有在所有已知窗口都大于 0，或者接口没有窗口且仍然允许使用时，才视为可用
    var isAvailableForDisplay: Bool {
        if windows.isEmpty {
            return allowed && limitReached == false
        }

        return windows.allSatisfy { window in
            window.remainingPercent > 0
        }
    }

    /// 从原始响应构建展示快照，统一处理计划名称和双窗口数据。
    init(response: CodexUsageResponse, fetchedAt: Date = Date()) {
        let primaryWindow = response.rateLimit?.primaryWindow.map {
            UsageWindowPresentation(
                id: "primary",
                title: "5 小时使用限额",
                subtitle: "\($0.remainingPercent)% 剩余",
                remainingPercent: $0.remainingPercent,
                usedPercent: $0.usedPercent,
                resetDate: $0.resetDate
            )
        }

        let secondaryWindow = response.rateLimit?.secondaryWindow.map {
            UsageWindowPresentation(
                id: "secondary",
                title: "每周使用限额",
                subtitle: "\($0.remainingPercent)% 剩余",
                remainingPercent: $0.remainingPercent,
                usedPercent: $0.usedPercent,
                resetDate: $0.resetDate
            )
        }

        self.email = response.email ?? "未知邮箱"
        self.planType = response.planType?.uppercased() ?? "UNKNOWN"
        self.allowed = response.rateLimit?.allowed ?? false
        self.limitReached = response.rateLimit?.limitReached ?? false
        self.fetchedAt = fetchedAt
        self.windows = [primaryWindow, secondaryWindow].compactMap { $0 }
    }

    /// 从 `registry.json.last_usage` 恢复展示快照。
    /// 这样即便应用刚启动、还没有重新发请求，也能先展示 `codex-auth` 之前缓存过的最近一次结果。
    init(
        storedSnapshot: CodexStoredUsageSnapshot,
        email: String,
        fallbackPlan: CodexPlanType?,
        fetchedAt: Date
    ) {
        let primaryWindow = storedSnapshot.primary.flatMap { window -> UsageWindowPresentation? in
            guard let resetDate = window.resetDate else {
                return nil
            }

            return UsageWindowPresentation(
                id: "primary",
                title: "5 小时限额",
                subtitle: "\(window.remainingPercent)% 剩余",
                remainingPercent: window.remainingPercent,
                usedPercent: Int(window.usedPercent.rounded()),
                resetDate: resetDate
            )
        }

        let secondaryWindow = storedSnapshot.secondary.flatMap { window -> UsageWindowPresentation? in
            guard let resetDate = window.resetDate else {
                return nil
            }

            return UsageWindowPresentation(
                id: "secondary",
                title: "每周限额",
                subtitle: "\(window.remainingPercent)% 剩余",
                remainingPercent: window.remainingPercent,
                usedPercent: Int(window.usedPercent.rounded()),
                resetDate: resetDate
            )
        }

        self.email = email
        self.planType = (storedSnapshot.planType ?? fallbackPlan ?? .unknown).badgeTitle
        self.allowed = [primaryWindow, secondaryWindow].compactMap(\.?.remainingPercent).contains { $0 > 0 }
        self.limitReached = self.allowed == false
        self.fetchedAt = fetchedAt
        self.windows = [primaryWindow, secondaryWindow].compactMap { $0 }
    }
}

extension AccountSubscriptionSnapshot {
    /// 从订阅接口响应构建展示快照。
    /// `active_until` 是 ISO-8601 时间字符串，这里提前解析成 `Date`，避免视图层重复做格式化准备。
    init(response: CodexSubscriptionResponse, fetchedAt: Date = Date()) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let parsedDate = response.activeUntil.flatMap { rawValue in
            formatter.date(from: rawValue) ?? ISO8601DateFormatter().date(from: rawValue)
        }

        self.planType = response.planType?.uppercased() ?? "UNKNOWN"
        self.activeUntil = parsedDate
        self.billingPeriod = response.billingPeriod ?? "unknown"
        self.willRenew = response.willRenew ?? false
        self.fetchedAt = fetchedAt
    }

    /// 从本地订阅缓存恢复展示快照。
    /// 这样应用重启后不需要等 12 小时刷新周期或网络请求完成，就能立即显示到期时间与年度会员标签。
    init(storedSnapshot: CodexStoredSubscriptionSnapshot) {
        self.planType = storedSnapshot.planType
        self.activeUntil = storedSnapshot.activeUntil.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        self.billingPeriod = storedSnapshot.billingPeriod
        self.willRenew = storedSnapshot.willRenew
        self.fetchedAt = Date(timeIntervalSince1970: TimeInterval(storedSnapshot.fetchedAt))
    }
}

extension CodexStoredSubscriptionSnapshot {
    /// 把运行时订阅快照转换成稳定的磁盘缓存结构。
    init(accountSubscriptionSnapshot: AccountSubscriptionSnapshot) {
        self.planType = accountSubscriptionSnapshot.planType
        self.activeUntil = accountSubscriptionSnapshot.activeUntil.map { Int64($0.timeIntervalSince1970) }
        self.billingPeriod = accountSubscriptionSnapshot.billingPeriod
        self.willRenew = accountSubscriptionSnapshot.willRenew
        self.fetchedAt = Int64(accountSubscriptionSnapshot.fetchedAt.timeIntervalSince1970)
    }
}

extension CodexStoredUsageSnapshot {
    /// 把当前接口响应转换回 `registry.last_usage`。
    /// GUI 不扩展 `registry.json` 字段，只写回参考实现已经定义好的结构。
    init(accountUsageSnapshot: AccountUsageSnapshot) {
        let primaryWindow = accountUsageSnapshot.windows.first(where: { $0.id == "primary" }).map { window in
            CodexStoredUsageWindow(
                usedPercent: Double(window.usedPercent),
                windowMinutes: 300,
                resetsAt: Int64(window.resetDate.timeIntervalSince1970)
            )
        }

        let secondaryWindow = accountUsageSnapshot.windows.first(where: { $0.id == "secondary" }).map { window in
            CodexStoredUsageWindow(
                usedPercent: Double(window.usedPercent),
                windowMinutes: 10080,
                resetsAt: Int64(window.resetDate.timeIntervalSince1970)
            )
        }

        self.primary = primaryWindow
        self.secondary = secondaryWindow
        self.credits = nil
        self.planType = CodexPlanType(rawValue: accountUsageSnapshot.planType.lowercased()) ?? .unknown
    }
}
