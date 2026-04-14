//
//  AccountEditorView.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import AppKit
import SwiftUI

/// 极简账号导入窗口。
/// 当前窗口只负责一件事情：让用户粘贴完整 curl 请求并立即保存。
/// 因此界面结构被刻意压缩成“标题 + 大输入区 + 底部操作栏”，避免任何分散注意力的表单项。
struct AccountEditorView: View {
    let initialDraft: CodexAccountDraft
    let onSave: (CodexAccountDraft) async throws -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft: CodexAccountDraft
    @State private var curlText = ""
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false

    init(
        initialDraft: CodexAccountDraft,
        onSave: @escaping (CodexAccountDraft) async throws -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.initialDraft = initialDraft
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        ZStack {
            palette.windowBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                VStack(spacing: 14) {
                    editorPanel

                    if errorMessage.isEmpty == false {
                        errorBanner
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .frame(width: 900, height: 700)
        .confirmationDialog(
            "确定删除这个账号吗？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let accountID = draft.id {
                Button("删除账号", role: .destructive) {
                    onDelete(accountID)
                    dismiss()
                }
            }

            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后会同时移除本地元数据和钥匙串中的凭据。")
        }
        .onAppear {
            promoteEditorWindow()
        }
        .onChange(of: initialDraft) { _, newValue in
            // 编辑窗口会被菜单栏重复复用。
            // 每次切换账号时，都必须把内部状态重置为新的草稿，避免残留上一次输入的 curl 内容。
            draft = newValue
            curlText = ""
            errorMessage = ""
            showingDeleteConfirmation = false
            promoteEditorWindow()
        }
    }

    /// 顶部只保留标题、获取方式说明和关闭按钮。
    /// 说明被压成一行副标题，既能回答“去哪里拿 curl”，又不会额外占用纵向空间。
    private var header: some View {
        HStack(spacing: 14) {
            Text(draft.id == nil ? "导入账号" : "更新账号")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(palette.primaryText)

            Text("浏览器网络面板中复制 “Copy as cURL”")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(palette.descriptionBackground)
                .clipShape(Capsule())

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("关闭", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(palette.headerBackground)
    }

    /// 主输入面板使用最直接的 `TextEditor`。
    /// 这里不再引入自定义 AppKit 文本视图，优先保证输入稳定、文字清晰可见、实现足够可维护。
    private var editorPanel: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $curlText)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(palette.editorText)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: curlText) { _, _ in
                    // 用户继续输入时，旧错误提示往往已经失效。
                    // 这里即时清理旧错误，避免界面在修正输入后依然停留在报错状态。
                    if errorMessage.isEmpty == false {
                        errorMessage = ""
                    }
                }

            if curlText.isEmpty {
                Text("在这里粘贴完整的 curl 请求…")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.placeholderText)
                    .padding(.leading, 24)
                    .padding(.top, 22)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }

    /// 底部固定操作区。
    /// 主操作始终停靠在右下角，并保留键盘快捷键，保证工具型窗口的操作效率。
    private var footer: some View {
        HStack(spacing: 10) {
            if draft.id != nil {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("删除账号", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("取消") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            Button {
                Task {
                    await save()
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("解析并保存", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(isSaving || curlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(palette.footerBackground)
                .overlay(alignment: .top) {
                    Divider()
                        .overlay(palette.divider)
                }
        )
    }

    /// 错误信息保持在输入区下方，用低饱和暖红提示异常，避免整体配色被破坏。
    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.errorAccent)

            Text(errorMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.errorText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.errorBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.errorBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let parsedCredential = try CurlImportParser.parse(command: curlText, fallback: draft.credential)
            var preparedDraft = draft
            preparedDraft.credential = parsedCredential

            // 账号名称不再要求手工录入。
            // 新账号会先使用占位名保存，首次刷新成功后自动替换成真实邮箱。
            if preparedDraft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                preparedDraft.displayName = ""
            }

            try await onSave(preparedDraft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 让独立窗口在从菜单栏打开时主动前置。
    /// 否则菜单栏失焦关闭后，用户容易误以为点击没有生效。
    private func promoteEditorWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            if let visibleWindow = NSApp.keyWindow ?? NSApp.mainWindow {
                visibleWindow.makeKeyAndOrderFront(nil)
                visibleWindow.orderFrontRegardless()
            }
        }
    }

    private var palette: CurlImporterPalette {
        CurlImporterPalette()
    }
}

/// 导入窗口统一配色。
/// 整体使用偏暖的浅灰层次，避免冷白界面显得生硬，同时保证正文区域的可读性足够高。
private struct CurlImporterPalette {
    let windowBackground = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.94, blue: 0.92),
            Color(red: 0.92, green: 0.91, blue: 0.88)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    let headerBackground = Color.white.opacity(0.72)
    let footerBackground = Color.white.opacity(0.80)
    let cardBackground = Color.white.opacity(0.92)
    let descriptionBackground = Color.white.opacity(0.84)
    let divider = Color.black.opacity(0.08)
    let cardBorder = Color(red: 0.72, green: 0.82, blue: 0.97)

    let primaryText = Color(red: 0.14, green: 0.15, blue: 0.17)
    let secondaryText = Color(red: 0.40, green: 0.42, blue: 0.46)
    let editorText = Color.black.opacity(0.88)
    let placeholderText = Color(red: 0.56, green: 0.58, blue: 0.62)

    let errorAccent = Color(red: 0.70, green: 0.24, blue: 0.19)
    let errorText = Color(red: 0.48, green: 0.18, blue: 0.16)
    let errorBackground = Color(red: 0.98, green: 0.91, blue: 0.88)
    let errorBorder = Color(red: 0.91, green: 0.62, blue: 0.55)
}
