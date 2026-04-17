//
//  UsageDashboardView.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

import AppKit
import SwiftUI

/// 面板展示模式。
/// 主窗口允许使用更舒展的布局；菜单栏窗口则优先保证“尽量一眼看到更多账号”。
enum UsageDashboardDisplayMode {
    case mainWindow
    case menuBar
}

/// 应用主面板。
/// 这个视图同时服务于主窗口和菜单栏窗口，通过 `displayMode` 切换为不同的密度。
struct UsageDashboardView: View {
    @ObservedObject var store: AppState
    let displayMode: UsageDashboardDisplayMode

    var body: some View {
        VStack(spacing: layout.outerSpacing) {
            headerSection

            if store.accounts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: layout.cardSpacing) {
                        ForEach(store.accounts) { account in
                            AccountCardView(
                                profile: account,
                                runtimeState: store.runtimeState(for: account.accountKey),
                                isActive: store.isActiveAccount(account.accountKey),
                                displayMode: displayMode,
                                onRefresh: {
                                    Task {
                                        await store.refreshAccount(account.accountKey)
                                    }
                                },
                                onSwitch: {
                                    do {
                                        try store.switchAccount(account.accountKey)
                                        return true
                                    } catch {
                                        showOperationErrorAlert(message: error.localizedDescription)
                                        return false
                                    }
                                },
                                onDelete: {
                                    do {
                                        try store.deleteAccount(account.accountKey)
                                    } catch {
                                        showOperationErrorAlert(message: error.localizedDescription)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.bottom, layout.bottomPadding)
                }
                .scrollIndicators(displayMode == .menuBar ? .hidden : .automatic)
            }

            footerSection
        }
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.bottomPadding)
        .background(panelBackground)
    }

    /// 顶部摘要与快捷操作。
    /// 菜单栏模式下会收缩字号和按钮占位，尽可能给账号列表腾出空间。
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: layout.headerSpacing) {
            if displayMode == .menuBar {
                HStack(alignment: .center, spacing: 8) {
                    Text("Codex 用量面板")
                        .font(.system(size: layout.titleFontSize, weight: .bold))
                        .foregroundStyle(palette.primaryText)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Button {
                            store.refreshAllAccounts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("刷新全部账号")

                        Button {
                            toggleLoginFlow()
                        } label: {
                            Label(store.isLaunchingLogin ? "取消登录" : "添加账号", systemImage: store.isLaunchingLogin ? "xmark.circle" : "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help(store.isLaunchingLogin ? "取消当前浏览器登录流程" : "打开浏览器登录 Codex 账号")
                    }
                }

                Text(summaryText)
                    .font(.system(size: layout.subtitleFontSize, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Codex 用量面板")
                            .font(.system(size: layout.titleFontSize, weight: .bold))
                            .foregroundStyle(palette.primaryText)

                        Text(summaryText)
                            .font(.system(size: layout.subtitleFontSize, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Button {
                            store.refreshAllAccounts()
                        } label: {
                            Label("刷新全部", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            toggleLoginFlow()
                        } label: {
                            Label(store.isLaunchingLogin ? "取消登录" : "添加账号", systemImage: store.isLaunchingLogin ? "xmark.circle" : "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .help(store.isLaunchingLogin ? "取消当前浏览器登录流程" : "打开浏览器登录 Codex 账号")
                    }
                }
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    /// 空状态面板。
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.isLaunchingLogin ? "正在等待登录完成" : "未发现账号")
                .font(.system(size: displayMode == .menuBar ? 16 : 18, weight: .bold))
                .foregroundStyle(palette.primaryText)

            Text(
                store.isLaunchingLogin
                ? "浏览器登录完成后账号会自动出现；如果暂时不登录，可以点击下方按钮取消。"
                : "会自动读取 `~/.codex` 里的已有账号。点击右上角“添加账号”即可直接走官方登录。"
            )
                .font(.system(size: displayMode == .menuBar ? 12 : 13))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                toggleLoginFlow()
            } label: {
                Label(store.isLaunchingLogin ? "取消登录" : "立即添加第一个账号", systemImage: store.isLaunchingLogin ? "xmark.circle" : "person.crop.circle.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(displayMode == .menuBar ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous))
        .padding(.horizontal, layout.horizontalPadding)
    }

    /// 底部辅助信息。
    private var footerSection: some View {
        HStack {
            Text("已连接 \(compactCodexHomePath)")
                .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)

            Spacer()

            Button("退出") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.link)
            .foregroundStyle(palette.actionText)
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    /// 菜单栏标题摘要。
    private var summaryText: String {
        if let activeAccount = store.accounts.first(where: { $0.accountKey == store.activeAccountKey }) {
            return "\(store.accounts.count) 个账号，当前使用 \(activeAccount.displayName)"
        }
        return store.isLaunchingLogin ? "浏览器登录进行中" : "\(store.accounts.count) 个账号"
    }

    /// 面板底色。
    /// 改用更稳定的浅暖灰，而不是大面积低对比白灰渐变，避免文字被背景吃掉。
    private var panelBackground: some View {
        palette.panelBackground
    }

    /// 卡片底色。
    private var cardBackground: some ShapeStyle {
        palette.cardBackground
    }

    /// 登录按钮的统一入口。
    /// 未登录时后台启动官方 `codex login` 并打开浏览器；登录中再次点击则取消当前流程。
    private func toggleLoginFlow() {
        if store.isLaunchingLogin {
            store.cancelLogin()
        } else {
            launchLogin()
        }
    }

    /// 直接触发官方浏览器登录。
    /// 菜单栏里只保留一个入口，避免再弹独立编辑窗口增加理解成本。
    private func launchLogin() {
        do {
            try store.launchLogin(deviceAuth: false)
        } catch {
            showOperationErrorAlert(message: error.localizedDescription)
        }
    }

    /// 底部路径统一压缩成更短的 `~/.codex` 风格。
    /// 用户只需要知道当前是否已经指向正确目录，不需要看一整串绝对路径。
    private var compactCodexHomePath: String {
        let actualHomePath = NSHomeDirectoryForUser(NSUserName()) ?? FileManager.default.homeDirectoryForCurrentUser.path
        if store.codexHomePath.hasPrefix(actualHomePath) {
            return "~" + store.codexHomePath.dropFirst(actualHomePath.count)
        }
        return store.codexHomePath
    }

    /// 菜单栏宿主下不适合挂 SwiftUI 的复杂对话框。
    /// 简单错误直接走 `NSAlert`，可以确保一定弹得出来、也一定能点击。
    private func showOperationErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "操作失败"
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// 统一的排版参数。
    private var layout: DashboardLayout {
        DashboardLayout(displayMode: displayMode)
    }

    /// 统一的高对比配色。
    private var palette: DashboardPalette {
        DashboardPalette()
    }
}

/// 单账号卡片。
/// 菜单栏模式采用更扁平的结构，减少垂直空间占用。
private struct AccountCardView: View {
    let profile: CodexRegistryAccount
    let runtimeState: AccountRuntimeState
    let isActive: Bool
    let displayMode: UsageDashboardDisplayMode
    let onRefresh: () -> Void
    let onSwitch: () -> Bool
    let onDelete: () -> Void

    /// 当前账号卡片是否处于鼠标悬停状态。
    /// 操作按钮默认隐藏，只在 hover 时显示，减少菜单栏面板里的常驻视觉噪音。
    @State private var isHoveringCard = false

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            header

            if let snapshot = runtimeState.snapshot {
                metricsSection(snapshot: snapshot)
            } else {
                placeholderSection
            }

            if let errorMessage = runtimeState.errorMessage, errorMessage.isEmpty == false {
                errorSection(message: errorMessage)
            }

            footer
        }
        .padding(layout.cardPadding)
        .frame(height: layout.cardHeight, alignment: .topLeading)
        .background(accountCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .stroke(accountCardBorderColor, lineWidth: isActive ? 1.6 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous))
        .shadow(
            color: accountCardShadowColor,
            radius: accountCardShadowRadius,
            x: 0,
            y: 4
        )
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringCard = isHovering
            }
        }
    }

    /// 账号名称、状态和快捷操作。
    private var header: some View {
        Group {
            if displayMode == .menuBar {
                HStack(alignment: .center, spacing: 8) {
                    Text(profile.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)

                    if let snapshot = runtimeState.snapshot {
                        planChip(text: snapshot.planType)

                        if shouldShowAnnualBadge(for: snapshot.planType) {
                            annualChip
                        }
                    }

                    if isActive {
                        activeStateChip
                    }

                    Spacer(minLength: 4)

                    compactActionControls
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.actionText)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(profile.displayName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(1)

                            if isActive {
                                activeStateChip
                            }
                        }

                        if let secondaryIdentityText = profile.secondaryIdentityText {
                            Text(secondaryIdentityText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(1)
                        } else {
                            Text(profile.email)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(1)
                        }

                        Text("直接复用 codex-auth 的 auth 快照与 registry")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        regularActionControls
                    }
                }
            }
        }
    }

    /// 已成功拉取数据时的主体内容。
    private func metricsSection(snapshot: AccountUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            if displayMode == .menuBar {
                if let identityText = profile.secondaryIdentityText ?? compactIdentityText(snapshot: snapshot) {
                    HStack(spacing: 6) {
                        Text(identityText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.secondaryIdentityText ?? snapshot.email)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            planChip(text: snapshot.planType)

                            if shouldShowAnnualBadge(for: snapshot.planType) {
                                annualChip
                            }
                        }
                    }

                    Spacer(minLength: 8)
                }
            }

            HStack(spacing: layout.metricSpacing) {
                ForEach(snapshot.windows) { window in
                    if displayMode == .menuBar {
                        CompactUsageWindowCard(window: window)
                    } else {
                        UsageWindowCard(window: window)
                    }
                }
            }
        }
    }

    /// 没有获取到数据时的占位提示。
    private var placeholderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(runtimeState.isRefreshing ? "正在拉取用量信息..." : "还没有拉取到数据")
                .font(.system(size: displayMode == .menuBar ? 12 : 13, weight: .medium))
                .foregroundStyle(palette.primaryText)

            Text(displayMode == .menuBar ? "检查 auth 快照是否已失效" : "如果这个账号最近出现 401，请先切换到该账号并在官方 Codex 客户端重新登录。")
                .font(.system(size: displayMode == .menuBar ? 11 : 12))
                .foregroundStyle(palette.secondaryText)
        }
        .padding(displayMode == .menuBar ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.placeholderBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 错误信息。
    private func errorSection(message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.errorText)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.errorBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 底部更新时间。
    private var footer: some View {
        HStack {
            footerStatusView

            Spacer()

            if runtimeState.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                    .frame(width: 14, height: 14)
            }
        }
    }

    /// 菜单栏里仅在“账号名”和“邮箱”不一致时显示邮箱，避免重复占空间。
    private func compactIdentityText(snapshot: AccountUsageSnapshot) -> String? {
        let profileName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let email = snapshot.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard profileName.isEmpty == false, email.isEmpty == false, profileName != email else {
            return nil
        }

        return snapshot.email
    }

    /// 菜单栏模式把更新时间缩成更短的时间戳，减少一整行文字的视觉重量。
    private func compactUpdatedText(_ date: Date) -> String {
        let timeText = date.formatted(date: .omitted, time: .shortened)
        return "更新 \(timeText)"
    }

    /// 底部状态文案会把更新时间和订阅到期时间合并为同一行，尽量不增加卡片高度。
    /// 底部状态区拆成独立视图后，可以对“到期时间”单独上色，
    /// 同时避免把不同语义的文本硬拼成一个字符串，后续扩展也更稳。
    @ViewBuilder
    private var footerStatusView: some View {
        HStack(spacing: 6) {
            Text(updatedStatusText)
                .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)

            if let expiryDescriptor = subscriptionExpiryDescriptor {
                Text(expiryDescriptor.text)
                    .font(.system(size: displayMode == .menuBar ? 9 : 10, weight: .bold))
                    .foregroundStyle(expiryDescriptor.textColor)
                    .padding(.horizontal, displayMode == .menuBar ? 6 : 7)
                    .padding(.vertical, displayMode == .menuBar ? 2 : 3)
                    .background(expiryDescriptor.backgroundColor)
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
        }
    }

    /// 更新时间仍然维持中性颜色，避免和订阅预警语义相互干扰。
    private var updatedStatusText: String {
        if let lastUpdatedAt = runtimeState.lastUpdatedAt {
            if displayMode == .menuBar {
                return compactUpdatedText(lastUpdatedAt)
            }
            return "最近更新：\(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
        }

        return displayMode == .menuBar ? "等待首次刷新" : "等待首次成功刷新"
    }

    /// 根据订阅剩余天数生成颜色语义：
    /// 剩余 1 天及以内使用错误色，剩余 5 天及以内使用警告色，其余保持中性弱强调。
    private var subscriptionExpiryDescriptor: SubscriptionExpiryDescriptor? {
        guard let activeUntil = runtimeState.subscriptionSnapshot?.activeUntil else {
            return nil
        }

        let remainingDays = subscriptionRemainingDays ?? Int.max

        let text: String
        if displayMode == .menuBar {
            text = "到期 \(activeUntil.formatted(date: .numeric, time: .omitted))"
        } else {
            text = "到期：\(activeUntil.formatted(date: .abbreviated, time: .omitted))"
        }

        if remainingDays <= 1 {
            return SubscriptionExpiryDescriptor(
                text: text,
                textColor: palette.errorText,
                backgroundColor: palette.errorBackground
            )
        }

        if remainingDays <= 5 {
            return SubscriptionExpiryDescriptor(
                text: text,
                textColor: palette.warningText,
                backgroundColor: palette.warningBackground
            )
        }

        return SubscriptionExpiryDescriptor(
            text: text,
            textColor: palette.secondaryText,
            backgroundColor: palette.mutedBackground.opacity(0.65)
        )
    }

    /// 活动状态标签。
    private var activeStateChip: some View {
        Text("当前使用")
            .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .bold))
            .foregroundStyle(palette.successText)
            .padding(.horizontal, displayMode == .menuBar ? 6 : 8)
            .padding(.vertical, displayMode == .menuBar ? 2 : 4)
            .background(palette.successBackground)
            .clipShape(Capsule())
    }

    private func planChip(text: String) -> some View {
        Text(compactPlanText(text))
            .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .bold))
            .foregroundStyle(palette.accentText)
            .padding(.horizontal, displayMode == .menuBar ? 6 : 8)
            .padding(.vertical, displayMode == .menuBar ? 2 : 4)
            .background(palette.accentBackground)
            .clipShape(Capsule())
    }

    /// 年度会员标签。
    /// 样式沿用套餐 badge 的高度和圆角，仅更换为更温和的金色语义，避免和“当前使用”的绿色状态混淆。
    private var annualChip: some View {
        Text("年度")
            .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .bold))
            .foregroundStyle(palette.warningText)
            .padding(.horizontal, displayMode == .menuBar ? 6 : 8)
            .padding(.vertical, displayMode == .menuBar ? 2 : 4)
            .background(palette.warningBackground)
            .clipShape(Capsule())
    }

    /// 菜单栏紧凑模式下的操作按钮组。
    /// 默认隐藏但保留布局空间，鼠标移入时淡入，避免 hover 时卡片宽度和文字截断发生跳变。
    private var compactActionControls: some View {
        HStack(spacing: 6) {
            if isActive == false {
                Button("切换") {
                    switchAccountAndNotify()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("切换到这个账号")
            }

            Button {
                onRefresh()
            } label: {
                refreshActionIcon
            }
            .buttonStyle(.borderless)
            .help("立即刷新")

            Button {
                confirmDeleteAccount()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除账号")
        }
        .opacity(actionControlsOpacity)
        .allowsHitTesting(shouldShowActionControls)
        .animation(.easeOut(duration: 0.12), value: shouldShowActionControls)
    }

    /// 主窗口密度下的操作按钮组。
    /// 虽然当前产品以菜单栏为主，但这里保持同一套 hover 行为，避免未来恢复主窗口时体验不一致。
    private var regularActionControls: some View {
        HStack(spacing: 8) {
            if isActive == false {
                Button {
                    switchAccountAndNotify()
                } label: {
                    Label("切换", systemImage: "arrow.left.arrow.right.circle")
                }
                .buttonStyle(.borderless)
                .help("切换到这个账号")
            }

            Button {
                onRefresh()
            } label: {
                refreshActionIcon
            }
            .buttonStyle(.borderless)
            .help("立即刷新")

            Button {
                confirmDeleteAccount()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除账号")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(palette.actionText)
        .opacity(actionControlsOpacity)
        .allowsHitTesting(shouldShowActionControls)
        .animation(.easeOut(duration: 0.12), value: shouldShowActionControls)
    }

    /// 刷新中时保留按钮可见，用户能明确看到当前账号正在执行操作。
    private var shouldShowActionControls: Bool {
        isHoveringCard || runtimeState.isRefreshing
    }

    /// 透明度单独拆出，后续如果要做更弱的常驻提示，只需要改这里。
    private var actionControlsOpacity: Double {
        shouldShowActionControls ? 1 : 0
    }

    /// 判断是否需要展示“年度”标签。
    /// 用户侧规则很直接：PLUS 账号距离订阅到期超过 31 天，就认为是年度会员。
    private func shouldShowAnnualBadge(for planType: String) -> Bool {
        guard compactPlanText(planType).uppercased() == "PLUS",
              let remainingDays = subscriptionRemainingDays else {
            return false
        }

        return remainingDays > 31
    }

    /// 订阅剩余天数统一集中计算，避免 footer 到期颜色和年度 badge 各自维护一套日期逻辑。
    private var subscriptionRemainingDays: Int? {
        guard let activeUntil = runtimeState.subscriptionSnapshot?.activeUntil else {
            return nil
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfExpiryDay = calendar.startOfDay(for: activeUntil)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfExpiryDay).day
    }

    /// 套餐徽标在菜单栏模式下缩成更短的文案，减少横向占位。
    private func compactPlanText(_ text: String) -> String {
        guard displayMode == .menuBar else {
            return text
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.uppercased() == "PLUS" {
            return "PLUS"
        }

        return normalized
    }

    private var layout: DashboardLayout {
        DashboardLayout(displayMode: displayMode)
    }

    private var palette: DashboardPalette {
        DashboardPalette()
    }

    private var cardBackground: some ShapeStyle {
        palette.cardBackground
    }

    /// 账号卡片背景。
    /// hover 时使用更亮、更冷一点的底色，让用户能明显感知当前鼠标所在卡片。
    private var accountCardBackground: Color {
        isHoveringCard ? palette.cardHoverBackground : palette.cardBackground
    }

    /// 账号卡片描边颜色。
    /// 活动账号仍保留蓝色强调；普通账号 hover 时提高描边对比度。
    private var accountCardBorderColor: Color {
        if isActive {
            return palette.accentText.opacity(isHoveringCard ? 0.65 : 0.45)
        }

        return isHoveringCard ? palette.cardHoverBorder : palette.cardBorder
    }

    /// 账号卡片阴影颜色。
    /// hover 时稍微增强阴影，不改变布局尺寸，只增强层级。
    private var accountCardShadowColor: Color {
        if displayMode == .menuBar {
            return Color.black.opacity(isHoveringCard ? 0.08 : 0.04)
        }

        return Color.black.opacity(isHoveringCard ? 0.12 : 0.08)
    }

    /// 账号卡片阴影半径。
    private var accountCardShadowRadius: CGFloat {
        if isActive {
            return displayMode == .menuBar ? (isHoveringCard ? 12 : 10) : (isHoveringCard ? 16 : 14)
        }

        return displayMode == .menuBar ? (isHoveringCard ? 9 : 6) : (isHoveringCard ? 14 : 12)
    }

    /// 刷新图标与转圈态使用固定尺寸容器，避免切换状态时撑高卡片、造成面板抖动。
    @ViewBuilder
    private var refreshActionIcon: some View {
        ZStack {
            Image(systemName: "arrow.clockwise")
                .opacity(runtimeState.isRefreshing ? 0 : 1)

            if runtimeState.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
            }
        }
        .frame(width: 14, height: 14)
    }

    /// 菜单栏弹窗会在失焦时自动关闭，SwiftUI `.alert` 挂在其上面会导致确认框无法交互。
    /// 这里改为直接弹原生 `NSAlert`，让确认流程脱离菜单栏宿主窗口，避免点击即消失。
    private func confirmDeleteAccount() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认删除账号？"
        alert.informativeText = "删除后会同时移除该账号的 registry 记录与 auth 快照：\(profile.displayName)"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")

        // 先把应用切到前台，确保无 Dock 菜单栏应用也能稳定弹出系统确认框。
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            onDelete()
        }
    }

    /// 切换账号后立即提醒用户重启 Codex 客户端。
    private func switchAccountAndNotify() {
        guard onSwitch() else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "已切换到 \(profile.displayName)"
        alert.informativeText = "新的账号快照已经写回到 `~/.codex/auth.json`。请重启 Codex / Codex App，让客户端主进程重新读取登录态。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// 主窗口模式使用的指标卡。
private struct UsageWindowCard: View {
    let window: UsageWindowPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(window.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondaryText)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(window.remainingPercent)%")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(palette.primaryText)

                Text("剩余")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            }

            progressBar

            Text("重置时间：\(formattedResetDate)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.metricCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.progressTrack)

                Capsule()
                    .fill(progressColor)
                    .frame(width: geometry.size.width * CGFloat(window.remainingPercent) / 100)
            }
        }
        .frame(height: 12)
    }

    private var formattedResetDate: String {
        let isToday = Calendar.current.isDateInToday(window.resetDate)
        if isToday {
            return window.resetDate.formatted(date: .omitted, time: .shortened)
        }
        return window.resetDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var progressColor: Color {
        window.remainingPercent > 30 ? palette.progressGood : palette.progressWarn
    }

    private var palette: DashboardPalette {
        DashboardPalette()
    }

}

/// 订阅到期展示描述。
/// 把颜色、文案与背景作为一个小模型集中管理，避免视图层到处写分支判断。
private struct SubscriptionExpiryDescriptor {
    let text: String
    let textColor: Color
    let backgroundColor: Color
}

/// 菜单栏模式使用的紧凑指标卡。
/// 这里压缩了字号和空白，优先保证同屏可以看到更多账号。
private struct CompactUsageWindowCard: View {
    let window: UsageWindowPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(compactTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(window.remainingPercent)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.progressTrack)

                    Capsule()
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(window.remainingPercent) / 100)
                }
            }
            .frame(height: 6)

            Text(formattedResetDate)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.metricCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var formattedResetDate: String {
        let isToday = Calendar.current.isDateInToday(window.resetDate)
        if isToday {
            return window.resetDate.formatted(date: .omitted, time: .shortened)
        }
        return window.resetDate.formatted(date: .numeric, time: .shortened)
    }

    /// 指标标题在菜单栏中进一步缩短，避免和百分比争抢横向空间。
    private var compactTitle: String {
        if window.title.contains("5小时") {
            return "5 小时限额"
        }

        if window.title.contains("每周") {
            return "每周限额"
        }

        return window.title.replacingOccurrences(of: "使用限额", with: "限额")
    }

    private var progressColor: Color {
        window.remainingPercent > 30 ? palette.progressGood : palette.progressWarn
    }

    private var palette: DashboardPalette {
        DashboardPalette()
    }
}

/// 面板统一布局参数。
private struct DashboardLayout {
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let horizontalPadding: CGFloat
    let outerSpacing: CGFloat
    let headerSpacing: CGFloat
    let cardSpacing: CGFloat
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let cardPadding: CGFloat
    let sectionSpacing: CGFloat
    let metricSpacing: CGFloat
    let cardCornerRadius: CGFloat
    let cardHeight: CGFloat?

    init(displayMode: UsageDashboardDisplayMode) {
        switch displayMode {
        case .mainWindow:
            topPadding = 16
            bottomPadding = 14
            horizontalPadding = 16
            outerSpacing = 14
            headerSpacing = 12
            cardSpacing = 12
            titleFontSize = 20
            subtitleFontSize = 12
            cardPadding = 14
            sectionSpacing = 12
            metricSpacing = 10
            cardCornerRadius = 18
            cardHeight = nil
        case .menuBar:
            topPadding = 8
            bottomPadding = 6
            horizontalPadding = 9
            outerSpacing = 7
            headerSpacing = 5
            cardSpacing = 4
            titleFontSize = 16
            subtitleFontSize = 10
            cardPadding = 7
            sectionSpacing = 3
            metricSpacing = 5
            cardCornerRadius = 14
            cardHeight = 116
        }
    }
}

/// 面板统一配色。
/// 这里统一使用动态颜色，保证浅色 / 暗色模式下都能保持足够的层级和可读性。
private struct DashboardPalette {
    let panelBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.90, 0.89, 0.85),
        dark: DashboardPalette.rgb(0.12, 0.12, 0.13)
    )

    let cardBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.965, 0.955, 0.935),
        dark: DashboardPalette.rgb(0.17, 0.17, 0.18)
    )
    let cardHoverBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.985, 0.975, 0.945),
        dark: DashboardPalette.rgb(0.22, 0.22, 0.24)
    )
    let metricCardBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.99, 0.99, 0.98),
        dark: DashboardPalette.rgb(0.10, 0.11, 0.12)
    )
    let placeholderBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.92, 0.92, 0.90),
        dark: DashboardPalette.rgb(0.19, 0.20, 0.21)
    )
    let mutedBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.87, 0.88, 0.85),
        dark: DashboardPalette.rgb(0.23, 0.24, 0.25)
    )
    let cardBorder = DashboardPalette.dynamicColor(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.18)
    )
    let cardHoverBorder = DashboardPalette.dynamicColor(
        light: NSColor.black.withAlphaComponent(0.20),
        dark: NSColor.white.withAlphaComponent(0.30)
    )

    let primaryText = Color.primary
    let secondaryText = Color(nsColor: .secondaryLabelColor)
    let actionText = Color(nsColor: .labelColor).opacity(0.88)

    let accentText = Color(nsColor: .systemBlue)
    let accentBackground = DashboardPalette.dynamicColor(
        light: NSColor.systemBlue.withAlphaComponent(0.16),
        dark: NSColor.systemBlue.withAlphaComponent(0.28)
    )

    let successText = Color(nsColor: .systemGreen)
    let successBackground = DashboardPalette.dynamicColor(
        light: NSColor.systemGreen.withAlphaComponent(0.18),
        dark: NSColor.systemGreen.withAlphaComponent(0.28)
    )

    let warningText = Color(nsColor: .systemOrange)
    let warningBackground = DashboardPalette.dynamicColor(
        light: NSColor.systemOrange.withAlphaComponent(0.22),
        dark: NSColor.systemOrange.withAlphaComponent(0.30)
    )

    let errorText = Color(nsColor: .systemRed)
    let errorBackground = DashboardPalette.dynamicColor(
        light: NSColor.systemRed.withAlphaComponent(0.16),
        dark: NSColor.systemRed.withAlphaComponent(0.26)
    )

    let progressTrack = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.86, 0.87, 0.88),
        dark: DashboardPalette.rgb(0.31, 0.32, 0.34)
    )
    let progressGood = Color(nsColor: .systemGreen)
    let progressWarn = Color(nsColor: .systemOrange)

    /// 生成固定 RGB 颜色。
    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    /// 生成随系统外观自动切换的动态颜色。
    /// 使用 `NSColor` 的动态 provider，而不是在视图层手动判断外观，这样所有引用处都会自动跟随系统切换。
    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
                return bestMatch == .darkAqua ? dark : light
            }
        )
    }
}
