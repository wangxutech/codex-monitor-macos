//
//  CurlImportParser.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import Foundation

/// 用于从浏览器复制的 curl 命令中提取认证头与关键请求头。
/// 这样用户可以直接从网络面板复制请求，减少手工拆分 Cookie 和 Header 的成本。
enum CurlImportParser {

    static func parse(command: String, fallback: CodexAccountCredential) throws -> CodexAccountCredential {
        let normalized = command
            .replacingOccurrences(of: "\\\n", with: " ")
            .replacingOccurrences(of: "\\\r\n", with: " ")

        let headerValues = extractFlagValues(flag: "-H", from: normalized)
        let cookieFromFlag = extractFlagValues(flag: "-b", from: normalized).last

        var parsedHeaders = [String: String]()
        for rawHeader in headerValues {
            guard let separatorIndex = rawHeader.firstIndex(of: ":") else {
                continue
            }

            let key = rawHeader[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawHeader[rawHeader.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else {
                continue
            }

            parsedHeaders[key.lowercased()] = value
        }

        let bearerToken = parsedHeaders["authorization"] ?? fallback.normalizedAuthorizationHeader
        let cookie = cookieFromFlag ?? parsedHeaders["cookie"] ?? fallback.cookie

        guard bearerToken.isEmpty == false || cookie.isEmpty == false else {
            throw CurlImportParserError.missingCredential
        }

        // 对于界面会主动设置的通用头，这里不再重复写入“额外请求头”，避免用户二次编辑时混淆。
        let ignoredKeys: Set<String> = [
            "accept",
            "accept-language",
            "authorization",
            "cache-control",
            "cookie",
            "pragma",
            "referer",
            "sec-ch-ua",
            "sec-ch-ua-mobile",
            "sec-ch-ua-platform",
            "sec-fetch-dest",
            "sec-fetch-mode",
            "sec-fetch-site",
            "user-agent",
            "x-openai-target-path",
            "x-openai-target-route",
            "oai-client-version",
            "oai-client-build-number",
            "oai-device-id",
            "oai-session-id",
            "oai-language"
        ]

        let additionalHeadersText = parsedHeaders
            .filter { ignoredKeys.contains($0.key) == false }
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")

        return CodexAccountCredential(
            bearerToken: bearerToken,
            cookie: cookie,
            clientVersion: parsedHeaders["oai-client-version"] ?? fallback.clientVersion,
            clientBuildNumber: parsedHeaders["oai-client-build-number"] ?? fallback.clientBuildNumber,
            deviceID: parsedHeaders["oai-device-id"] ?? fallback.deviceID,
            sessionID: parsedHeaders["oai-session-id"] ?? fallback.sessionID,
            language: parsedHeaders["oai-language"] ?? fallback.language,
            userAgent: parsedHeaders["user-agent"] ?? fallback.userAgent,
            additionalHeadersText: additionalHeadersText.isEmpty ? fallback.additionalHeadersText : additionalHeadersText
        )
    }

    /// 提取 curl 中某个 flag 后面跟随的引号字符串，兼容单引号和双引号两种格式。
    private static func extractFlagValues(flag: String, from command: String) -> [String] {
        let escapedFlag = NSRegularExpression.escapedPattern(for: flag)
        let pattern = "\(escapedFlag)\\s+(?:'([^']*)'|\"([^\"]*)\")"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(command.startIndex..., in: command)
        let matches = regex.matches(in: command, range: range)

        return matches.compactMap { match in
            for captureIndex in 1..<match.numberOfRanges {
                let captureRange = match.range(at: captureIndex)
                guard captureRange.location != NSNotFound, let range = Range(captureRange, in: command) else {
                    continue
                }

                return String(command[range])
            }

            return nil
        }
    }
}

enum CurlImportParserError: LocalizedError {
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "没有在 curl 文本中解析到 Authorization 或 Cookie，请确认复制的是完整请求。"
        }
    }
}
