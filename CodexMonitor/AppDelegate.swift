//
//  AppDelegate.swift
//  CodexMonitor
//
//  Created by harry on 2026/4/13.
//

import SwiftUI

/// 纯菜单栏版 SwiftUI macOS 应用入口。
/// 应用启动后不再主动创建主窗口，只保留菜单栏入口。
/// 这样可以满足“没有 Dock 图标、没有主界面、只通过菜单栏交互”的产品形态。
@main
struct CodexMonitorApp: App {

    /// 菜单栏面板的固定宽度。
    /// 宽度保持稳定可以避免账号数量变化时窗口左右跳动，保证菜单栏弹窗的视觉一致性。
    private let menuBarPanelWidth: CGFloat = 416

    /// 整个应用共享的一份状态对象。
    /// 菜单栏面板内直接完成登录、切换、刷新和删除，所有状态都集中在这里。
    @StateObject private var appState = AppState()

    var body: some Scene {
        // 菜单栏是应用唯一常驻入口。
        // 启动后不会再弹出主界面，用户只需要从菜单栏展开面板即可。
        MenuBarExtra {
            UsageDashboardView(store: appState, displayMode: .menuBar)
                .frame(width: menuBarPanelWidth, height: menuBarPanelHeight)
        } label: {
            Label(appState.menuBarTitle, systemImage: "chart.bar.fill")
        }
        .menuBarExtraStyle(.window)
    }

    /// 菜单栏弹窗高度会随着账号数量自动伸缩。
    /// 高度计算基于当前筛选后的可见账号数量，而不是原始账号总数。
    /// 这样当用户切换到底部的“可用账号”时，面板不会因为隐藏掉的账号而保留无意义的空白高度。
    ///
    /// 账号列表最多按 7 张卡片计算，再多账号时交给内部滚动区域处理。
    private var menuBarPanelHeight: CGFloat {
        if appState.accounts.isEmpty {
            return 260
        }

        let visibleAccountCount = min(max(appState.filteredAccountCount, 1), 7)

        // 这里的基础高度只包含标题栏、摘要、顶部/底部边距和底部退出区域。
        // 账号卡片区域单独按 120 高度计算，避免只有 1 个账号时仍显示大面积空白面板。
        let chromeHeight: CGFloat = 86

        // 菜单栏卡片在 `UsageDashboardView` 中固定为 120 高度。
        // 7 个账号的卡片主体高度为 840；卡片之间保留 4pt 间距，确保视觉分隔但不显著增加面板体积。
        let accountCardHeight: CGFloat = 118
        let cardSpacing: CGFloat = 4
        let accountPanelHeight = CGFloat(visibleAccountCount) * accountCardHeight +
            CGFloat(max(visibleAccountCount - 1, 0)) * cardSpacing

        return chromeHeight + accountPanelHeight
    }
}
