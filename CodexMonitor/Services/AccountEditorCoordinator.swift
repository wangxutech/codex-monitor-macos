//
//  AccountEditorCoordinator.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import Foundation

/// 账号编辑窗口协调器。
/// 该对象专门负责“当前要编辑哪一个草稿”，并为独立编辑窗口提供共享数据来源。
/// 之所以单独抽出来，是因为菜单栏窗口点击“添加账号 / 编辑账号”后，
/// 原来的 `.sheet` 会随着菜单栏窗口失焦而自动关闭，不适合做复杂表单编辑。
@MainActor
final class AccountEditorCoordinator: ObservableObject {

    /// 当前窗口正在编辑的草稿。
    /// 每次用户点击“添加账号”或“编辑账号”时，都会先覆盖为最新草稿，再打开独立窗口。
    @Published private(set) var currentDraft = CodexAccountDraft()

    /// 更新当前草稿，供独立编辑窗口读取。
    func present(draft: CodexAccountDraft) {
        currentDraft = draft
    }
}
