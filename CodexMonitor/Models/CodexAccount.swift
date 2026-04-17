//
//  CodexAccount.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import Foundation

/// `codex-auth` 当前使用的 registry schema 版本。
/// GUI 版会尽量只读写这一版字段，避免把参考工程的文件结构写乱。
enum CodexRegistrySchema {
    static let currentVersion = 3
}

/// `registry.json` 里的套餐枚举。
/// 这里直接对齐 `codex-auth` 的原始字符串，保证和现有磁盘数据完全兼容。
enum CodexPlanType: String, Codable, Equatable {
    case free
    case plus
    case prolite
    case pro
    case team
    case business
    case enterprise
    case edu
    case unknown

    /// 统一输出给卡片徽标的短文案。
    /// 菜单栏空间非常紧，这里尽量保持短、稳、可扫读。
    var badgeTitle: String {
        switch self {
        case .free:
            return "FREE"
        case .plus:
            return "PLUS"
        case .prolite:
            return "PRO LITE"
        case .pro:
            return "PRO"
        case .team, .business:
            return "BUSINESS"
        case .enterprise:
            return "ENTERPRISE"
        case .edu:
            return "EDU"
        case .unknown:
            return "UNKNOWN"
        }
    }
}

/// `registry.json` 中记录的认证模式。
enum CodexAuthMode: String, Codable, Equatable {
    case chatgpt
    case apikey
}

/// `registry.json.auto_switch` 配置块。
/// GUI 当前不会直接编辑这部分，但读写时必须保留原值，避免把参考项目配置清空。
struct CodexAutoSwitchConfig: Codable, Equatable {
    var enabled: Bool = false
    var threshold5hPercent: Int = 10
    var thresholdWeeklyPercent: Int = 5

    enum CodingKeys: String, CodingKey {
        case enabled
        case threshold5hPercent = "threshold_5h_percent"
        case thresholdWeeklyPercent = "threshold_weekly_percent"
    }
}

/// `registry.json.api` 配置块。
/// 与参考实现保持同字段名，保证切换到 `codex-auth` CLI 时配置仍然一致。
struct CodexAPIConfig: Codable, Equatable {
    var usage: Bool = true
    var account: Bool = true
}

/// 本地 rollout 去重签名。
/// 当前 GUI 只做透传，不主动消费这个字段，但保存 registry 时必须保留。
struct CodexRolloutSignature: Codable, Equatable {
    var path: String
    var eventTimestampMs: Int64

    enum CodingKeys: String, CodingKey {
        case path
        case eventTimestampMs = "event_timestamp_ms"
    }
}

/// 额度窗口快照。
/// 结构对齐 `registry.last_usage.primary / secondary`。
struct CodexStoredUsageWindow: Codable, Equatable {
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Int64?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    /// 当前 UI 主要展示剩余百分比，因此这里统一提供派生值。
    var remainingPercent: Int {
        max(0, Int((100 - usedPercent).rounded()))
    }

    /// 统一把 Unix 秒时间戳转换成 `Date`，便于视图格式化。
    var resetDate: Date? {
        guard let resetsAt else {
            return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(resetsAt))
    }
}

/// 额度余额快照。
/// 目前只在解析 registry 时保留原值，不额外做展示逻辑。
struct CodexStoredCreditsSnapshot: Codable, Equatable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}

/// `registry.last_usage` 的完整结构。
struct CodexStoredUsageSnapshot: Codable, Equatable {
    var primary: CodexStoredUsageWindow?
    var secondary: CodexStoredUsageWindow?
    var credits: CodexStoredCreditsSnapshot?
    var planType: CodexPlanType?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case credits
        case planType = "plan_type"
    }
}

/// `registry.json.accounts[]` 的单条账号记录。
/// `Identifiable` 直接使用 `account_key`，这样可以和 `codex-auth` 的记录主键完全一致。
struct CodexRegistryAccount: Identifiable, Codable, Equatable {
    var id: String { accountKey }

    var accountKey: String
    var chatgptAccountID: String
    var chatgptUserID: String
    var email: String
    var alias: String
    var accountName: String?
    var plan: CodexPlanType?
    var authMode: CodexAuthMode?
    var createdAt: Int64
    var lastUsedAt: Int64?
    var lastUsage: CodexStoredUsageSnapshot?
    var lastUsageAt: Int64?
    var lastLocalRollout: CodexRolloutSignature?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case chatgptAccountID = "chatgpt_account_id"
        case chatgptUserID = "chatgpt_user_id"
        case email
        case alias
        case accountName = "account_name"
        case plan
        case authMode = "auth_mode"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case lastLocalRollout = "last_local_rollout"
    }

    /// 卡片主标题的优先级完全参考 `codex-auth` 的人类识别习惯：
    /// `alias > account_name > email`。
    var displayName: String {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAlias.isEmpty == false {
            return trimmedAlias
        }

        let trimmedAccountName = accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedAccountName.isEmpty == false {
            return trimmedAccountName
        }

        return email
    }

    /// 当标题不是邮箱时，再额外补一行邮箱，避免重复占空间。
    var secondaryIdentityText: String? {
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedDisplayName.isEmpty == false, normalizedDisplayName != normalizedEmail else {
            return nil
        }

        return email
    }

    /// 套餐徽标优先使用最新用量快照里的 `plan_type`，其次才退回 registry 静态字段。
    /// 这样可以尽量和实际接口返回保持一致。
    var resolvedPlan: CodexPlanType? {
        lastUsage?.planType ?? plan
    }
}

/// 整个 `accounts/registry.json`。
/// 保存时会固定写回 schema v3，避免和参考项目文件格式产生偏差。
struct CodexRegistryDocument: Codable, Equatable {
    var schemaVersion: Int
    var activeAccountKey: String?
    var activeAccountActivatedAtMs: Int64?
    var autoSwitch: CodexAutoSwitchConfig
    var api: CodexAPIConfig
    var accounts: [CodexRegistryAccount]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case activeAccountKey = "active_account_key"
        case activeAccountActivatedAtMs = "active_account_activated_at_ms"
        case autoSwitch = "auto_switch"
        case api
        case accounts
    }

    static let empty = CodexRegistryDocument(
        schemaVersion: CodexRegistrySchema.currentVersion,
        activeAccountKey: nil,
        activeAccountActivatedAtMs: nil,
        autoSwitch: CodexAutoSwitchConfig(),
        api: CodexAPIConfig(),
        accounts: []
    )
}

/// `auth.json` / `*.auth.json` 的标准结构。
/// 当前 GUI 只关心 ChatGPT Web 认证字段，因此按最小必要集合建模。
struct CodexStoredAuthDocument: Codable, Equatable {
    var authMode: String?
    var openAIAPIKey: String?
    var tokens: CodexStoredAuthTokens?
    var lastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
    }
}

/// `auth.json.tokens` 字段。
struct CodexStoredAuthTokens: Codable, Equatable {
    var idToken: String?
    var accessToken: String?
    var refreshToken: String?
    var accountID: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
    }
}

/// 从 `auth.json` 解析出的运行态认证上下文。
/// 这个类型不直接落盘，只用于登录导入、切换和 API 请求。
struct CodexAuthContext: Equatable {
    var email: String
    var chatgptAccountID: String
    var chatgptUserID: String
    var recordKey: String
    var accessToken: String
    var refreshToken: String?
    var lastRefresh: String?
    var plan: CodexPlanType?
    var authMode: CodexAuthMode
}
