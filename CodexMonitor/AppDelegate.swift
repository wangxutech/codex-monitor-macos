//
//  AppDelegate.swift
//  CodexMonitor
//
//  Created by harry on 2026/4/13.
//

import SwiftUI

/// 纯菜单栏版 SwiftUI macOS 应用入口。
/// 应用启动后不再主动创建主窗口，只保留菜单栏入口和按需打开的编辑窗口。
/// 这样可以满足“没有 Dock 图标、没有主界面、只通过菜单栏交互”的产品形态。
@main
struct CodexMonitorApp: App {

    /// 菜单栏面板的固定宽度。
    /// 宽度保持稳定可以避免账号数量变化时窗口左右跳动，保证菜单栏弹窗的视觉一致性。
    private let menuBarPanelWidth: CGFloat = 416

    /// 整个应用共享的一份状态对象。
    /// 独立编辑窗口与菜单栏面板共用这份状态，确保两个入口看到的是同一份账号和用量数据。
    @StateObject private var appState = AppState()

    /// 独立账号编辑窗口的协调器。
    /// 菜单栏面板与主窗口都会通过它把“当前要编辑的草稿”传递给编辑窗口。
    @StateObject private var editorCoordinator = AccountEditorCoordinator()

    var body: some Scene {
        /// 独立账号编辑窗口。
        /// 这里改用单实例 `Window`，避免应用启动时系统自动打开一个空白编辑窗口。
        Window("账号编辑", id: "account-editor") {
            AccountEditorView(
                initialDraft: editorCoordinator.currentDraft,
                onSave: { draft in
                    _ = try appState.saveAccount(from: draft)
                },
                onDelete: { accountID in
                    appState.deleteAccount(accountID)
                }
            )
            .frame(width: 900, height: 700)
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentSize)

        // 菜单栏是应用唯一常驻入口。
        // 启动后不会再弹出主界面，用户只需要从菜单栏展开面板即可。
        MenuBarExtra {
            UsageDashboardView(store: appState, displayMode: .menuBar)
                .environmentObject(editorCoordinator)
                .frame(width: menuBarPanelWidth, height: menuBarPanelHeight)
        } label: {
            Label(appState.menuBarTitle, systemImage: "chart.bar.fill")
        }
        .menuBarExtraStyle(.window)
    }

    /// 菜单栏弹窗高度会随着账号数量自动伸缩，但只按最多 5 个账号估算。
    /// 这样可以满足“少账号时不显得空、大约 5 个账号时尽量一眼看全、更多账号时再滚动”的交互目标。
    private var menuBarPanelHeight: CGFloat {
        if appState.accounts.isEmpty {
            return 260
        }

        let visibleAccountCount = min(max(appState.accounts.count, 1), 5)
        // 这里的基础高度包含标题栏、摘要、副边距和底部退出区域。
        // 之前的估算偏小，导致 3 个账号时仍然出现滚动条，因此这里适当上调基础值。
        let baseHeight: CGFloat = 148

        // 单账号高度按当前“标题 + 双额度卡 + 底部状态行”的真实体积估算。
        // 取值偏保守一些，优先保证 3 个账号无滚动；账号继续增加时再交给整体高度上限裁剪。
        let perAccountHeight: CGFloat = 224
        let computedHeight = baseHeight + CGFloat(visibleAccountCount) * perAccountHeight

        // 菜单栏弹窗高度改为固定上限 600。
        // 这样可以直接规避不同屏幕、不同菜单栏宿主环境下的高度估算偏差，
        // 超过上限后统一交给内部滚动区域处理，避免面板出现大块空白。
        return min(max(computedHeight, 420), 600)
    }
}
