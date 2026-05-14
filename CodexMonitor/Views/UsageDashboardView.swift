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

    /// 当前筛选条件下真正需要渲染的账号列表。
    /// 视图层统一使用这个集合，避免“列表已经过滤了，但空状态和摘要还是原始数据”的割裂体验。
    private var displayedAccounts: [CodexRegistryAccount] {
        store.filteredAccounts
    }

    var body: some View {
        VStack(spacing: layout.outerSpacing) {
            headerSection

            if shouldShowEmptyState {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: layout.cardSpacing) {
                        ForEach(displayedAccounts) { account in
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
                    .padding(.bottom, displayMode == .menuBar ? 1 : layout.bottomPadding)
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
                HStack(alignment: .center, spacing: 7) {
                    Text("Codex 用量面板")
                        .font(.system(size: layout.titleFontSize, weight: .bold))
                        .foregroundStyle(palette.primaryText)

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
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
        VStack(alignment: .leading, spacing: displayMode == .menuBar ? 9 : 12) {
            Text(emptyStateTitle)
                .font(.system(size: displayMode == .menuBar ? 16 : 18, weight: .bold))
                .foregroundStyle(palette.primaryText)

            Text(emptyStateDescription)
                .font(.system(size: displayMode == .menuBar ? 12 : 13))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if shouldShowEmptyStateAction {
                Button {
                    toggleLoginFlow()
                } label: {
                    Label(store.isLaunchingLogin ? "取消登录" : "立即添加第一个账号", systemImage: store.isLaunchingLogin ? "xmark.circle" : "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(displayMode == .menuBar ? 13 : 20)
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
        HStack(spacing: displayMode == .menuBar ? 6 : 10) {
            HStack(spacing: displayMode == .menuBar ? 6 : 8) {
                Text("显示")
                    .font(.system(size: displayMode == .menuBar ? 10 : 12, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)

                Picker(
                    "显示账号范围",
                    selection: Binding(
                        get: { store.accountVisibilityFilter },
                        set: { newValue in
                            store.updateAccountVisibilityFilter(newValue)
                        }
                    )
                ) {
                    ForEach(AccountVisibilityFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: displayMode == .menuBar ? 98 : 120)

                HStack(spacing: displayMode == .menuBar ? 4 : 8) {
                    ForEach(AccountPlanFilter.allCases) { filter in
                        Toggle(
                            filter.title,
                            isOn: Binding(
                                get: { store.isPlanFilterEnabled(filter) },
                                set: { isEnabled in
                                    store.updatePlanFilter(filter, isEnabled: isEnabled)
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: displayMode == .menuBar ? 9 : 12, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .help("显示 \(filter.title) 类型账号")
                    }
                }
            }

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
            if store.accountVisibilityFilter == .availableAccounts {
                return "显示 \(displayedAccounts.count)/\(store.accounts.count) 个可用账号，当前使用 \(activeAccount.displayName)"
            }

            if displayedAccounts.count != store.accounts.count {
                return "显示 \(displayedAccounts.count)/\(store.accounts.count) 个账号，当前使用 \(activeAccount.displayName)"
            }

            return "\(store.accounts.count) 个账号，当前使用 \(activeAccount.displayName)"
        }

        if store.accountVisibilityFilter == .availableAccounts {
            return store.isLaunchingLogin
                ? "浏览器登录进行中"
                : "显示 \(displayedAccounts.count)/\(store.accounts.count) 个可用账号"
        }

        if displayedAccounts.count != store.accounts.count {
            return store.isLaunchingLogin ? "浏览器登录进行中" : "显示 \(displayedAccounts.count)/\(store.accounts.count) 个账号"
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

    /// 是否应该显示空状态。
    /// 除了“根本没有账号”之外，当用户切到“可用账号”且当前没有任何可用账号时，也需要给出明确反馈。
    private var shouldShowEmptyState: Bool {
        store.accounts.isEmpty || displayedAccounts.isEmpty
    }

    /// 空状态标题根据当前场景动态切换。
    private var emptyStateTitle: String {
        if store.accounts.isEmpty {
            return store.isLaunchingLogin ? "正在等待登录完成" : "未发现账号"
        }

        return "当前没有可用账号"
    }

    /// 空状态说明文案。
    /// 有账号但都不可用时，重点提示用户可以切回“所有账号”继续查看详细额度。
    private var emptyStateDescription: String {
        if store.accounts.isEmpty {
            return store.isLaunchingLogin
                ? "浏览器登录完成后账号会自动出现；如果暂时不登录，可以点击下方按钮取消。"
                : "会自动读取 `~/.codex` 里的已有账号。点击右上角“添加账号”即可直接走官方登录。"
        }

        if store.accountVisibilityFilter == .availableAccounts {
            return "当前筛选没有匹配账号。你可以在底部切回“所有账号”，或勾选更多账号类型查看完整信息。"
        }

        return "当前账号类型筛选没有匹配账号。请在底部勾选更多账号类型。"
    }

    /// 只有在“尚未添加任何账号”这类空状态下，才需要继续显示登录入口。
    private var shouldShowEmptyStateAction: Bool {
        store.accounts.isEmpty
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
                HStack(alignment: .center, spacing: 6) {
                    Text(profile.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accountTitleColor)
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

                    if isUnavailable {
                        unavailableStateChip
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
                                .foregroundStyle(accountTitleColor)
                                .lineLimit(1)

                            if isActive {
                                activeStateChip
                            }

                            if isUnavailable {
                                unavailableStateChip
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
        VStack(alignment: .leading, spacing: displayMode == .menuBar ? 5 : 8) {
            Text(runtimeState.isRefreshing ? "正在拉取用量信息..." : "还没有拉取到数据")
                .font(.system(size: displayMode == .menuBar ? 12 : 13, weight: .medium))
                .foregroundStyle(palette.primaryText)

            Text(displayMode == .menuBar ? "检查 auth 快照是否已失效" : "如果这个账号最近出现 401，请先切换到该账号并在官方 Codex 客户端重新登录。")
                .font(.system(size: displayMode == .menuBar ? 11 : 12))
                .foregroundStyle(palette.secondaryText)
        }
        .padding(displayMode == .menuBar ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.placeholderBackground)
        .clipShape(RoundedRectangle(cornerRadius: displayMode == .menuBar ? 8 : 12, style: .continuous))
    }

    /// 错误信息。
    private func errorSection(message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.errorText)
            .padding(displayMode == .menuBar ? 8 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.errorBackground)
            .clipShape(RoundedRectangle(cornerRadius: displayMode == .menuBar ? 8 : 12, style: .continuous))
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
        HStack(spacing: displayMode == .menuBar ? 5 : 6) {
            Text(updatedStatusText)
                .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)

            if let expiryDescriptor = subscriptionExpiryDescriptor {
                Text(expiryDescriptor.text)
                    .font(.system(size: displayMode == .menuBar ? 9 : 10, weight: .bold))
                    .foregroundStyle(expiryDescriptor.textColor)
                    .padding(.horizontal, displayMode == .menuBar ? 5 : 7)
                    .padding(.vertical, displayMode == .menuBar ? 1.5 : 3)
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
            .foregroundStyle(palette.activeBadgeText)
            .padding(.horizontal, displayMode == .menuBar ? 5 : 8)
            .padding(.vertical, displayMode == .menuBar ? 1.5 : 4)
            .background(palette.activeBadgeBackground)
            .overlay(
                Capsule()
                    .stroke(palette.activeBadgeBorder, lineWidth: 0.8)
            )
            .clipShape(Capsule())
    }

    /// 不可用状态标签。
    /// 当任意额度窗口已经归零时，卡片本身会弱化，这个标签负责给用户一个明确的文字锚点。
    private var unavailableStateChip: some View {
        Text("不可用")
            .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .bold))
            .foregroundStyle(palette.unavailableBadgeText)
            .padding(.horizontal, displayMode == .menuBar ? 5 : 8)
            .padding(.vertical, displayMode == .menuBar ? 1.5 : 4)
            .background(palette.unavailableBadgeBackground)
            .overlay(
                Capsule()
                    .stroke(palette.unavailableBadgeBorder, lineWidth: 0.8)
            )
            .clipShape(Capsule())
    }

    private func planChip(text: String) -> some View {
        let style = planChipStyle(for: text)

        return Text(compactPlanText(text))
            .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .bold))
            .foregroundStyle(style.textColor)
            .padding(.horizontal, displayMode == .menuBar ? 5 : 8)
            .padding(.vertical, displayMode == .menuBar ? 1.5 : 4)
            .background(style.backgroundColor)
            .overlay(
                Capsule()
                    .stroke(style.borderColor, lineWidth: 0.8)
            )
            .clipShape(Capsule())
    }

    /// 套餐 badge 使用独立色系，避免 PRO / PLUS / FREE 在快速扫视时都像同一个蓝色状态。
    /// 这里只按展示文案归类，兼容接口可能返回的大小写或 `PRO LITE` 这类扩展套餐。
    private func planChipStyle(for text: String) -> ChipStyle {
        let normalized = compactPlanText(text).uppercased()

        if normalized.contains("PRO") {
            return ChipStyle(
                textColor: palette.proPlanText,
                backgroundColor: palette.proPlanBackground,
                borderColor: palette.proPlanBorder
            )
        }

        if normalized == "PLUS" {
            return ChipStyle(
                textColor: palette.plusPlanText,
                backgroundColor: palette.plusPlanBackground,
                borderColor: palette.plusPlanBorder
            )
        }

        if normalized == "FREE" {
            return ChipStyle(
                textColor: palette.freePlanText,
                backgroundColor: palette.freePlanBackground,
                borderColor: palette.freePlanBorder
            )
        }

        return ChipStyle(
            textColor: palette.accentText,
            backgroundColor: palette.accentBackground,
            borderColor: palette.accentText.opacity(0.20)
        )
    }

    /// 年度会员标签。
    /// 样式沿用套餐 badge 的高度和圆角，仅更换为更温和的金色语义，避免和“当前使用”的绿色状态混淆。
    private var annualChip: some View {
        Text("年度")
            .font(.system(size: displayMode == .menuBar ? 9 : 11, weight: .bold))
            .foregroundStyle(palette.annualBadgeText)
            .padding(.horizontal, displayMode == .menuBar ? 5 : 8)
            .padding(.vertical, displayMode == .menuBar ? 1.5 : 4)
            .background(palette.annualBadgeBackground)
            .overlay(
                Capsule()
                    .stroke(palette.annualBadgeBorder, lineWidth: 0.8)
            )
            .clipShape(Capsule())
    }

    /// 菜单栏紧凑模式下的操作按钮组。
    /// 默认隐藏但保留布局空间，鼠标移入时淡入，避免 hover 时卡片宽度和文字截断发生跳变。
    private var compactActionControls: some View {
        HStack(spacing: 5) {
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
    /// hover 时使用更亮、更冷一点的底色；不可用账号使用更冷的灰底，让它和仍可继续使用的账号拉开层级。
    private var accountCardBackground: Color {
        if isUnavailable {
            return isHoveringCard ? palette.unavailableCardHoverBackground : palette.unavailableCardBackground
        }

        return isHoveringCard ? palette.cardHoverBackground : palette.cardBackground
    }

    /// 账号卡片描边颜色。
    /// 活动账号保留蓝色强调；不可用账号使用偏橙灰描边，让用户不用读数值也能先感知状态。
    private var accountCardBorderColor: Color {
        if isActive {
            return palette.accentText.opacity(isHoveringCard ? 0.65 : 0.45)
        }

        if isUnavailable {
            return palette.unavailableCardBorder.opacity(isHoveringCard ? 0.80 : 0.58)
        }

        return isHoveringCard ? palette.cardHoverBorder : palette.cardBorder
    }

    /// 账号卡片阴影颜色。
    /// hover 时稍微增强阴影，不改变布局尺寸，只增强层级。
    private var accountCardShadowColor: Color {
        if displayMode == .menuBar {
            return Color.black.opacity(isHoveringCard ? 0.06 : 0.025)
        }

        return Color.black.opacity(isHoveringCard ? 0.12 : 0.08)
    }

    /// 账号卡片阴影半径。
    private var accountCardShadowRadius: CGFloat {
        if isActive {
            return displayMode == .menuBar ? (isHoveringCard ? 8 : 6) : (isHoveringCard ? 16 : 14)
        }

        return displayMode == .menuBar ? (isHoveringCard ? 7 : 4) : (isHoveringCard ? 14 : 12)
    }

    /// 当前卡片是否不可用。
    /// 只要任意已知额度窗口为 0，`AccountUsageSnapshot` 就会把它判定为不可用。
    private var isUnavailable: Bool {
        runtimeState.snapshot?.isAvailableForDisplay == false
    }

    /// 不可用账号的标题稍微降权，但仍保持可读，不把用户需要识别的邮箱压得过淡。
    private var accountTitleColor: Color {
        isUnavailable ? palette.primaryText.opacity(0.74) : palette.primaryText
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

    /// 切换账号后提醒用户 Codex App 已自动重启。
    private func switchAccountAndNotify() {
        guard onSwitch() else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "已切换到 \(profile.displayName)"
        alert.informativeText = "新的账号快照已经写回到 `~/.codex/auth.json`，Codex App 会自动重启以读取新的登录态。"
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

/// 通用胶囊 badge 样式。
/// 套餐、当前账号、不可用状态都使用同一组字段，这样高度、描边和背景层级可以保持一致。
private struct ChipStyle {
    let textColor: Color
    let backgroundColor: Color
    let borderColor: Color
}

/// 菜单栏模式使用的紧凑指标卡。
/// 这里压缩了字号和空白，优先保证同屏可以看到更多账号。
private struct CompactUsageWindowCard: View {
    let window: UsageWindowPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(compactTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(window.remainingPercent)%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
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
            .frame(height: 5)

            Text(formattedResetDate)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.metricCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            topPadding = 7
            bottomPadding = 4
            horizontalPadding = 8
            outerSpacing = 4
            headerSpacing = 4
            cardSpacing = 2
            titleFontSize = 16
            subtitleFontSize = 10
            cardPadding = 6
            sectionSpacing = 2
            metricSpacing = 4
            cardCornerRadius = 10
            cardHeight = 98
        }
    }
}

/// 面板统一配色。
/// 这里统一使用动态颜色，保证浅色 / 暗色模式下都能保持足够的层级和可读性。
private struct DashboardPalette {
    let panelBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.94, 0.945, 0.95),
        dark: DashboardPalette.rgb(0.12, 0.12, 0.13)
    )

    let cardBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.985, 0.985, 0.975),
        dark: DashboardPalette.rgb(0.17, 0.17, 0.18)
    )
    let cardHoverBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(1.00, 1.00, 0.99),
        dark: DashboardPalette.rgb(0.22, 0.22, 0.24)
    )
    let unavailableCardBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.95, 0.95, 0.94),
        dark: DashboardPalette.rgb(0.145, 0.145, 0.150)
    )
    let unavailableCardHoverBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.965, 0.96, 0.94),
        dark: DashboardPalette.rgb(0.185, 0.180, 0.170)
    )
    let metricCardBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.99, 0.99, 0.98),
        dark: DashboardPalette.rgb(0.10, 0.11, 0.12)
    )
    let placeholderBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.93, 0.94, 0.945),
        dark: DashboardPalette.rgb(0.19, 0.20, 0.21)
    )
    let mutedBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.88, 0.90, 0.91),
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
    let unavailableCardBorder = DashboardPalette.dynamicColor(
        light: NSColor.systemOrange.withAlphaComponent(0.46),
        dark: NSColor.systemOrange.withAlphaComponent(0.62)
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
    let activeBadgeText = Color.white
    let activeBadgeBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.05, 0.55, 0.22),
        dark: DashboardPalette.rgb(0.12, 0.66, 0.30)
    )
    let activeBadgeBorder = DashboardPalette.dynamicColor(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.18)
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

    let proPlanText = Color.white
    let proPlanBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.11, 0.45, 0.96),
        dark: DashboardPalette.rgb(0.18, 0.52, 1.00)
    )
    let proPlanBorder = DashboardPalette.dynamicColor(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.18)
    )

    let plusPlanText = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.72, 0.31, 0.00),
        dark: DashboardPalette.rgb(1.00, 0.72, 0.30)
    )
    let plusPlanBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(1.00, 0.86, 0.58),
        dark: NSColor.systemOrange.withAlphaComponent(0.22)
    )
    let plusPlanBorder = DashboardPalette.dynamicColor(
        light: NSColor.systemOrange.withAlphaComponent(0.36),
        dark: NSColor.systemOrange.withAlphaComponent(0.45)
    )

    let freePlanText = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.26, 0.33, 0.40),
        dark: DashboardPalette.rgb(0.82, 0.86, 0.90)
    )
    let freePlanBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.84, 0.88, 0.92),
        dark: DashboardPalette.rgb(0.24, 0.27, 0.30)
    )
    let freePlanBorder = DashboardPalette.dynamicColor(
        light: NSColor.black.withAlphaComponent(0.14),
        dark: NSColor.white.withAlphaComponent(0.18)
    )

    let unavailableBadgeText = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.70, 0.24, 0.05),
        dark: DashboardPalette.rgb(1.00, 0.63, 0.42)
    )
    let unavailableBadgeBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(1.00, 0.86, 0.78),
        dark: NSColor.systemRed.withAlphaComponent(0.20)
    )
    let unavailableBadgeBorder = DashboardPalette.dynamicColor(
        light: NSColor.systemRed.withAlphaComponent(0.28),
        dark: NSColor.systemRed.withAlphaComponent(0.42)
    )

    let annualBadgeText = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(0.58, 0.25, 0.00),
        dark: DashboardPalette.rgb(1.00, 0.78, 0.38)
    )
    let annualBadgeBackground = DashboardPalette.dynamicColor(
        light: DashboardPalette.rgb(1.00, 0.79, 0.42),
        dark: NSColor.systemYellow.withAlphaComponent(0.24)
    )
    let annualBadgeBorder = DashboardPalette.dynamicColor(
        light: NSColor.systemOrange.withAlphaComponent(0.42),
        dark: NSColor.systemYellow.withAlphaComponent(0.50)
    )

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
