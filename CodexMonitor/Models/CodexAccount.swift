//
//  CodexAccount.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import Foundation

/// 非敏感账号资料。
/// 这部分信息会写入 UserDefaults，便于应用启动后快速恢复账号列表和刷新策略。
struct CodexAccountProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var note: String
    var refreshIntervalSeconds: Int
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        note: String = "",
        refreshIntervalSeconds: Int = 60,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.note = note
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 敏感请求配置。
/// 包括 Bearer Token、Cookie 等认证信息，统一保存在系统钥匙串中，避免直接明文写入本地偏好。
struct CodexAccountCredential: Codable, Equatable {
    var bearerToken: String
    var cookie: String
    var clientVersion: String
    var clientBuildNumber: String
    var deviceID: String
    var sessionID: String
    var language: String
    var userAgent: String
    var additionalHeadersText: String

    static let empty = CodexAccountCredential(
        bearerToken: "",
        cookie: "",
        clientVersion: "",
        clientBuildNumber: "",
        deviceID: "",
        sessionID: "",
        language: "zh-CN",
        userAgent: CodexAccountCredential.defaultUserAgent,
        additionalHeadersText: ""
    )

    /// 使用一个较新的桌面浏览器 UA 作为默认值，减少服务端对缺失 UA 的拒绝概率。
    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"

    /// 自动补齐 Bearer 前缀，兼容用户既可能粘贴纯 token，也可能直接粘贴完整 Authorization 值。
    var normalizedAuthorizationHeader: String {
        let trimmed = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return ""
        }

        if trimmed.lowercased().hasPrefix("bearer ") {
            return trimmed
        }

        return "Bearer \(trimmed)"
    }

    /// 将“每行一个 Header”的文本格式解析为字典，便于组装请求。
    var parsedAdditionalHeaders: [String: String] {
        additionalHeadersText
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { partialResult, line in
                let rawLine = String(line)
                guard let separatorIndex = rawLine.firstIndex(of: ":") else {
                    return
                }

                let key = rawLine[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = rawLine[rawLine.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard key.isEmpty == false, value.isEmpty == false else {
                    return
                }

                partialResult[key] = value
            }
    }

    /// 从 Bearer Token 中推导当前 ChatGPT 账号 ID。
    /// `subscriptions` 接口需要 `account_id` 查询参数，而用户导入 curl 时通常不会单独填写它。
    /// 这里直接解析 JWT 的 payload，读取 `https://api.openai.com/auth.chatgpt_account_id` 对应字段，
    /// 这样就能复用同一套认证信息去请求订阅数据。
    var inferredAccountID: String? {
        let authorization = normalizedAuthorizationHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authorization.isEmpty == false else {
            return nil
        }

        let token: String
        if authorization.lowercased().hasPrefix("bearer ") {
            token = String(authorization.dropFirst("Bearer ".count))
        } else {
            token = authorization
        }

        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            return nil
        }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard
            let data = Data(base64Encoded: base64),
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let payload = jsonObject as? [String: Any]
        else {
            return nil
        }

        if let authInfo = payload["https://api.openai.com/auth"] as? [String: Any],
           let accountID = authInfo["chatgpt_account_id"] as? String,
           accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return accountID
        }

        return nil
    }
}

/// 编辑器使用的草稿模型。
/// 把资料与敏感配置聚合到一起，便于表单一次性提交。
struct CodexAccountDraft: Equatable {
    var id: UUID?
    var displayName: String
    var note: String
    var refreshIntervalSeconds: Int
    var isEnabled: Bool
    var credential: CodexAccountCredential

    init(
        id: UUID? = nil,
        displayName: String = "",
        note: String = "",
        refreshIntervalSeconds: Int = 60,
        isEnabled: Bool = true,
        credential: CodexAccountCredential = .empty
    ) {
        self.id = id
        self.displayName = displayName
        self.note = note
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.isEnabled = isEnabled
        self.credential = credential
    }

    init(profile: CodexAccountProfile, credential: CodexAccountCredential) {
        self.id = profile.id
        self.displayName = profile.displayName
        self.note = profile.note
        self.refreshIntervalSeconds = profile.refreshIntervalSeconds
        self.isEnabled = profile.isEnabled
        self.credential = credential
    }
}
