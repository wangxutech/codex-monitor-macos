//
//  StatusBarController.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import AppKit
import SwiftUI

/// 管理菜单栏按钮与 NSPopover 展示。
/// 之所以不直接用普通窗口，是为了实现用户期望的“点击顶部图标即可展开紧凑面板”的交互。
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init<Content: View>(rootView: Content) {
        // 菜单栏入口改为自适应宽度。
        // 这里优先保证“用户一定能看见入口”，哪怕系统图标渲染失败，也还能显示文字标题。
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover(rootView: rootView)
    }

    func update(title: String) {
        guard let button = statusItem.button else {
            return
        }

        // 菜单栏始终保留可见文字。
        // 这样即使图标因为模板渲染、系统样式或符号兼容问题没有显示，用户仍能在菜单栏看到入口。
        button.title = title
        button.toolTip = title
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        // 尝试加载系统符号图标。
        // 如果图标不可用，后面仍会通过文字标题保证菜单栏入口可见。
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = NSImage(
            systemSymbolName: "chart.bar.fill",
            accessibilityDescription: "Codex 用量监控"
        )?.withSymbolConfiguration(symbolConfiguration)
        image?.isTemplate = true

        // 默认先给一个固定可见标题，应用状态更新后会被替换成实时摘要。
        button.title = "Codex"
        button.image = image
        button.imagePosition = image == nil ? .noImage : .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Codex 用量监控"
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.action = #selector(togglePopover(_:))
        button.target = self

        // 显式保持状态栏项目可见，避免后续因为系统状态切换导致按钮被隐藏。
        statusItem.isVisible = true
    }

    private func configurePopover<Content: View>(rootView: Content) {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 460, height: 680)
        popover.contentViewController = NSHostingController(
            rootView: rootView
                .frame(width: 460, height: 680)
        )
    }
}
