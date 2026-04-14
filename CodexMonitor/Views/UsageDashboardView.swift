//
//  UsageDashboardView.swift
//  CodexMonitor
//
//  Created by Codex on 2026/4/13.
//

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

    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var editorCoordinator: AccountEditorCoordinator

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
                                runtimeState: store.runtimeState(for: account.id),
                                displayMode: displayMode,
                                onToggleEnabled: { store.setAccountEnabled(account.id, isEnabled: $0) },
                                onRefresh: {
                                    Task {
                                        await store.refreshAccount(account.id)
                                    }
                                },
                                onDelete: {
                                    store.deleteAccount(account.id)
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
                            openEditor(for: nil)
                        } label: {
                            Label("添加账号", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
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
                            openEditor(for: nil)
                        } label: {
                            Label("添加账号", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    /// 空状态面板。
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("还没有配置账号")
                .font(.system(size: displayMode == .menuBar ? 16 : 18, weight: .bold))
                .foregroundStyle(palette.primaryText)

            Text("建议直接从浏览器网络面板复制完整 curl 请求，在添加账号弹窗中一键解析。账号凭据会保存在系统钥匙串，方便你在多个 Codex 账号之间比较剩余额度。")
                .font(.system(size: displayMode == .menuBar ? 12 : 13))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openEditor(for: nil)
            } label: {
                Label("立即添加第一个账号", systemImage: "plus.circle.fill")
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
            if displayMode == .menuBar {
                Text("凭据保存在系统钥匙串")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text("敏感凭据保存在系统钥匙串")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
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
        let enabledCount = store.accounts.filter(\.isEnabled).count
        let successCount = store.accounts.filter { store.runtimeState(for: $0.id).snapshot != nil }.count
        return "\(store.accounts.count) 个账号，\(enabledCount) 个启用，\(successCount) 个已拉取成功"
    }

    /// 面板底色。
    /// 改用更稳定的浅暖灰，而不是大面积低对比白灰渐变，避免文字被背景吃掉。
    private var panelBackground: some View {
        LinearGradient(
            colors: [
                palette.panelTop,
                palette.panelBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 卡片底色。
    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                palette.cardTop,
                palette.cardBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 打开独立账号编辑窗口。
    /// 菜单栏窗口即使随后失焦关闭，编辑窗口仍会继续存在，不会中断操作。
    private func openEditor(for accountID: UUID?) {
        editorCoordinator.present(draft: store.draft(for: accountID))

        DispatchQueue.main.async {
            // 菜单栏窗口在按钮点击后会立刻进入失焦关闭流程。
            // 把真正的开窗动作延后到下一轮主线程，可以确保独立编辑窗口仍然稳定弹出。
            openWindow(id: "account-editor")
            NSApp.activate(ignoringOtherApps: true)
        }
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
    let profile: CodexAccountProfile
    let runtimeState: AccountRuntimeState
    let displayMode: UsageDashboardDisplayMode
    let onToggleEnabled: (Bool) -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void

    /// 删除操作需要二次确认，避免在菜单栏里误触后直接丢失账号。
    @State private var isShowingDeleteConfirmation = false

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
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous))
        .shadow(
            color: displayMode == .menuBar ? Color.black.opacity(0.04) : Color.black.opacity(0.08),
            radius: displayMode == .menuBar ? 6 : 12,
            x: 0,
            y: 4
        )
        .alert("确认删除账号？", isPresented: $isShowingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("删除后会同时移除该账号的本地配置和系统钥匙串凭据：\(profile.displayName)")
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
                    }

                    Spacer(minLength: 4)

                    Toggle("", isOn: Binding(
                        get: { profile.isEnabled },
                        set: onToggleEnabled
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                    Button {
                        onRefresh()
                    } label: {
                        refreshActionIcon
                    }
                    .buttonStyle(.borderless)
                    .help("立即刷新")

                    Button {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除账号")
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

                            statusChip
                        }

                        Text("每 \(profile.refreshIntervalSeconds) 秒自动刷新")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)

                        if profile.note.isEmpty == false {
                            Text(profile.note)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { profile.isEnabled },
                            set: onToggleEnabled
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                        HStack(spacing: 8) {
                            Button {
                                onRefresh()
                            } label: {
                                refreshActionIcon
                            }
                            .buttonStyle(.borderless)
                            .help("立即刷新")

                            Button {
                                isShowingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("删除账号")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.actionText)
                    }
                }
            }
        }
    }

    /// 已成功拉取数据时的主体内容。
    private func metricsSection(snapshot: AccountUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            if displayMode == .menuBar {
                if let identityText = compactIdentityText(snapshot: snapshot) {
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
                        Text(snapshot.email)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            planChip(text: snapshot.planType)
                            availabilityChip(snapshot: snapshot)
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

            Text(displayMode == .menuBar ? "检查 Cookie / Token 是否完整" : "请检查 Cookie、Bearer Token 和高级请求头是否完整。")
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

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfExpiryDay = calendar.startOfDay(for: activeUntil)
        let remainingDays = calendar.dateComponents([.day], from: startOfToday, to: startOfExpiryDay).day ?? Int.max

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

    /// 启用状态标签。
    /// 使用深绿色文字而不是高亮绿色正文，提升对比度同时保留状态语义。
    private var statusChip: some View {
        Text(profile.isEnabled ? "启用中" : "已暂停")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(profile.isEnabled ? palette.successText : palette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(profile.isEnabled ? palette.successBackground : palette.mutedBackground)
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

    private func availabilityChip(snapshot: AccountUsageSnapshot) -> some View {
        let text: String
        let textColor: Color
        let backgroundColor: Color

        if snapshot.limitReached {
            text = "已触发限制"
            textColor = palette.errorText
            backgroundColor = palette.errorBackground
        } else if snapshot.allowed {
            text = "可继续使用"
            textColor = palette.successText
            backgroundColor = palette.successBackground
        } else {
            text = "等待确认"
            textColor = palette.secondaryText
            backgroundColor = palette.mutedBackground
        }

        return Text(text)
            .font(.system(size: displayMode == .menuBar ? 10 : 11, weight: .bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, displayMode == .menuBar ? 7 : 8)
            .padding(.vertical, displayMode == .menuBar ? 3 : 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var layout: DashboardLayout {
        DashboardLayout(displayMode: displayMode)
    }

    private var palette: DashboardPalette {
        DashboardPalette()
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                palette.cardTop,
                palette.cardBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        case .menuBar:
            topPadding = 8
            bottomPadding = 6
            horizontalPadding = 9
            outerSpacing = 7
            headerSpacing = 5
            cardSpacing = 6
            titleFontSize = 16
            subtitleFontSize = 10
            cardPadding = 7
            sectionSpacing = 3
            metricSpacing = 5
            cardCornerRadius = 14
        }
    }
}

/// 面板统一配色。
/// 配色目标不是“更炫”，而是提高信息对比度和层级辨识度。
private struct DashboardPalette {
    let panelTop = Color(red: 0.96, green: 0.95, blue: 0.92)
    let panelBottom = Color(red: 0.91, green: 0.90, blue: 0.87)

    let cardTop = Color.white.opacity(0.97)
    let cardBottom = Color(red: 0.95, green: 0.94, blue: 0.92)
    let metricCardBackground = Color.white.opacity(0.94)
    let placeholderBackground = Color(red: 0.92, green: 0.92, blue: 0.90)
    let mutedBackground = Color(red: 0.87, green: 0.88, blue: 0.85)
    let cardBorder = Color.black.opacity(0.10)

    let primaryText = Color(red: 0.14, green: 0.15, blue: 0.17)
    let secondaryText = Color(red: 0.34, green: 0.36, blue: 0.39)
    let actionText = Color(red: 0.21, green: 0.24, blue: 0.28)

    let accentText = Color(red: 0.05, green: 0.30, blue: 0.70)
    let accentBackground = Color(red: 0.84, green: 0.90, blue: 0.98)

    let successText = Color(red: 0.08, green: 0.34, blue: 0.14)
    let successBackground = Color(red: 0.84, green: 0.92, blue: 0.82)

    let warningText = Color(red: 0.57, green: 0.34, blue: 0.06)
    let warningBackground = Color(red: 0.98, green: 0.91, blue: 0.78)

    let errorText = Color(red: 0.64, green: 0.17, blue: 0.17)
    let errorBackground = Color(red: 0.98, green: 0.88, blue: 0.86)

    let progressTrack = Color(red: 0.86, green: 0.87, blue: 0.88)
    let progressGood = Color(red: 0.15, green: 0.64, blue: 0.22)
    let progressWarn = Color(red: 0.90, green: 0.58, blue: 0.18)
}
