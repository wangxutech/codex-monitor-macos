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
}
