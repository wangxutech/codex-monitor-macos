//
//  CodexUsageAPI.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import Foundation

/// 专门负责向 Codex 用量接口发起请求。
/// 这里尽量把请求构造细节封装起来，让上层状态管理只关心“拿到结果”或“拿到错误”。
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

    func fetchUsage(with credential: CodexAccountCredential) async throws -> AccountUsageSnapshot {
        let request = try makeUsageRequest(with: credential)
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
    /// 与用量接口共用同一套认证头，只是额外需要 `account_id` 作为查询参数。
    func fetchSubscription(with credential: CodexAccountCredential) async throws -> AccountSubscriptionSnapshot {
        guard let accountID = credential.inferredAccountID else {
            throw CodexUsageAPIError.invalidConfiguration("无法从当前账号凭据中解析 account_id。")
        }

        let request = try makeSubscriptionRequest(with: credential, accountID: accountID)
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

    /// 根据用户录入的账号配置，组装一次完整的用量请求。
    private func makeUsageRequest(with credential: CodexAccountCredential) throws -> URLRequest {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw CodexUsageAPIError.invalidURL
        }

        return try makeAuthorizedRequest(
            url: url,
            credential: credential,
            referer: "https://chatgpt.com/codex/cloud/settings/usage",
            targetPath: "/backend-api/wham/usage",
            targetRoute: "/backend-api/wham/usage"
        )
    }

    /// 组装订阅请求。
    private func makeSubscriptionRequest(with credential: CodexAccountCredential, accountID: String) throws -> URLRequest {
        guard
            var components = URLComponents(string: "https://chatgpt.com/backend-api/subscriptions")
        else {
            throw CodexUsageAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "account_id", value: accountID)
        ]

        guard let url = components.url else {
            throw CodexUsageAPIError.invalidURL
        }

        return try makeAuthorizedRequest(
            url: url,
            credential: credential,
            referer: "https://chatgpt.com/codex/cloud/settings/usage",
            targetPath: "/backend-api/subscriptions",
            targetRoute: "/backend-api/subscriptions"
        )
    }

    /// 所有 ChatGPT Web 接口共用的一套基础认证头组装逻辑。
    /// 把公共部分收敛到这里，可以避免用量接口和订阅接口后续出现头部不一致。
    private func makeAuthorizedRequest(
        url: URL,
        credential: CodexAccountCredential,
        referer: String,
        targetPath: String,
        targetRoute: String
    ) throws -> URLRequest {

        let authorization = credential.normalizedAuthorizationHeader
        let cookie = credential.cookie.trimmingCharacters(in: .whitespacesAndNewlines)

        guard authorization.isEmpty == false else {
            throw CodexUsageAPIError.invalidConfiguration("请填写 Authorization Bearer Token。")
        }

        guard cookie.isEmpty == false else {
            throw CodexUsageAPIError.invalidConfiguration("请填写 Cookie。")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("no-cache", forHTTPHeaderField: "cache-control")
        request.setValue("no-cache", forHTTPHeaderField: "pragma")
        request.setValue(referer, forHTTPHeaderField: "referer")
        request.setValue(targetPath, forHTTPHeaderField: "x-openai-target-path")
        request.setValue(targetRoute, forHTTPHeaderField: "x-openai-target-route")
        request.setValue(authorization, forHTTPHeaderField: "authorization")
        request.setValue(cookie, forHTTPHeaderField: "cookie")
        request.setValue(nonEmptyValue(credential.language, fallback: "zh-CN"), forHTTPHeaderField: "oai-language")
        request.setValue(nonEmptyValue(credential.userAgent, fallback: CodexAccountCredential.defaultUserAgent), forHTTPHeaderField: "user-agent")

        if credential.clientBuildNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            request.setValue(credential.clientBuildNumber, forHTTPHeaderField: "oai-client-build-number")
        }

        if credential.clientVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            request.setValue(credential.clientVersion, forHTTPHeaderField: "oai-client-version")
        }

        if credential.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            request.setValue(credential.deviceID, forHTTPHeaderField: "oai-device-id")
        }

        if credential.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            request.setValue(credential.sessionID, forHTTPHeaderField: "oai-session-id")
        }

        // 允许用户补充一些暂未内建的 Header，避免服务端策略变化后必须重新发版。
        for (key, value) in credential.parsedAdditionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    private func nonEmptyValue(_ candidate: String, fallback: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

enum CodexUsageAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidConfiguration(String)
    case requestFailed(statusCode: Int, message: String?)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "接口地址无效。"
        case .invalidResponse:
            return "服务端返回了无法识别的响应。"
        case .invalidConfiguration(let message):
            return message
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
