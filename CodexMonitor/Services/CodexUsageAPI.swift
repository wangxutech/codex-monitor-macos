//
//  CodexUsageAPI.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import Foundation

/// 负责请求 ChatGPT Web 侧的用量与订阅接口。
/// 这一版实现不再依赖浏览器导出的 curl，而是直接复用 `auth.json` 里的 `access_token` 与 `chatgpt_account_id`。
final class CodexUsageAPI {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        self.session = URLSession(configuration: configuration)
    }

    /// 拉取用量快照。
    /// 请求头与 `codex-auth` 保持同一思路：`Authorization + ChatGPT-Account-Id + User-Agent`。
    func fetchUsage(with context: CodexAuthContext) async throws -> AccountUsageSnapshot {
        let request = try makeUsageRequest(with: context)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexUsageAPIError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: responseText
            )
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(CodexUsageResponse.self, from: data)
            return AccountUsageSnapshot(response: payload)
        } catch {
            throw CodexUsageAPIError.decodingFailed(error)
        }
    }

    /// 拉取订阅信息。
    /// 订阅接口要求 query 中包含 `account_id`，值直接使用当前 `chatgpt_account_id`。
    func fetchSubscription(with context: CodexAuthContext) async throws -> AccountSubscriptionSnapshot {
        let request = try makeSubscriptionRequest(with: context)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexUsageAPIError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: responseText
            )
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(CodexSubscriptionResponse.self, from: data)
            return AccountSubscriptionSnapshot(response: payload)
        } catch {
            throw CodexUsageAPIError.decodingFailed(error)
        }
    }

    /// 拉取当前用户作用域下的账号名称信息。
    /// 这一步对齐 `codex-auth` 的 `accounts/check` 行为，主要用于把 Team 工作区名称补齐到 registry。
    func fetchAccountNames(with context: CodexAuthContext) async throws -> [CodexAccountNameEntry] {
        let request = try makeAccountNameRequest(with: context)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexUsageAPIError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: responseText
            )
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(CodexAccountCheckResponse.self, from: data)
            return payload.accountEntries
        } catch {
            throw CodexUsageAPIError.decodingFailed(error)
        }
    }

    /// 构造用量请求。
    private func makeUsageRequest(with context: CodexAuthContext) throws -> URLRequest {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw CodexUsageAPIError.invalidURL
        }

        return makeAuthorizedRequest(url: url, context: context)
    }

    /// 构造订阅请求。
    private func makeSubscriptionRequest(with context: CodexAuthContext) throws -> URLRequest {
        guard var components = URLComponents(string: "https://chatgpt.com/backend-api/subscriptions") else {
            throw CodexUsageAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "account_id", value: context.chatgptAccountID)
        ]

        guard let url = components.url else {
            throw CodexUsageAPIError.invalidURL
        }

        return makeAuthorizedRequest(url: url, context: context)
    }

    /// 构造工作区名称刷新请求。
    private func makeAccountNameRequest(with context: CodexAuthContext) throws -> URLRequest {
        guard let url = URL(string: "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27") else {
            throw CodexUsageAPIError.invalidURL
        }

        return makeAuthorizedRequest(url: url, context: context)
    }

    /// 统一的授权请求头。
    /// 这里刻意保持简洁，不再继续依赖 Cookie、Session ID 等浏览器态 Header。
    private func makeAuthorizedRequest(url: URL, context: CodexAuthContext) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(context.chatgptAccountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// 参考 `codex-auth` 默认使用的桌面浏览器 UA。
    private static let browserUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
}

/// `accounts/check` 返回的单个账号名称条目。
/// 这里只保留 GUI 真正需要的两个字段：`account_id` 与 `name`。
struct CodexAccountNameEntry: Decodable, Equatable {
    let accountID: String
    let accountName: String?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case accountName = "name"
    }
}

/// `accounts/check` 顶层响应中的单条账号包装结构。
private struct CodexAccountCheckAccountWrapper: Decodable {
    let account: CodexAccountNameEntry?
}

/// `accounts/check` 返回格式是一个动态 key 的对象。
/// 这里把 `default` 之外的每个条目解包成 `[CodexAccountNameEntry]`，方便后续直接按账号 ID 回写。
private struct CodexAccountCheckResponse: Decodable {
    let accounts: [String: CodexAccountCheckAccountWrapper]

    var accountEntries: [CodexAccountNameEntry] {
        accounts.compactMap { key, value in
            guard key != "default" else {
                return nil
            }

            guard let entry = value.account else {
                return nil
            }

            let normalizedAccountID = entry.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedAccountID.isEmpty == false else {
                return nil
            }

            let normalizedName = entry.accountName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CodexAccountNameEntry(
                accountID: normalizedAccountID,
                accountName: normalizedName?.isEmpty == false ? normalizedName : nil
            )
        }
    }
}

enum CodexUsageAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "接口地址无效。"
        case .invalidResponse:
            return "服务端返回了无法识别的响应。"
        case .requestFailed(let statusCode, let message):
            if let message, message.isEmpty == false {
                return "请求失败（HTTP \(statusCode)）：\(message)"
            }
            return "请求失败（HTTP \(statusCode)）。"
        case .decodingFailed(let error):
            return "解析返回数据失败：\(error.localizedDescription)"
        }
    }
}
