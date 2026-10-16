import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TokenBarWidgets: WidgetBundle {
    var body: some Widget { QuotaLiveActivity() }
}

struct QuotaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QuotaActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Token Bar", systemImage: "chart.bar.fill").font(.caption.bold())
                    Spacer()
                    Label("點此刷新", systemImage: "arrow.clockwise").font(.caption)
                }
                HStack(alignment: .top, spacing: 14) {
                    ActivityColumn(summary: context.state.claude)
                    Rectangle().fill(.secondary.opacity(0.2)).frame(width: 1)
                    ActivityColumn(summary: context.state.codex)
                }
                .fixedSize(horizontal: false, vertical: true)
                Text(context.isStale ? "資料待更新 · 點卡片重新查詢" : "最後讀取的額度 · 點卡片開 App 刷新")
                    .font(.caption2).foregroundStyle(context.isStale ? Color.orange : Color.secondary)
            }
            .padding(14)
            .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.12))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(URL(string: "tokenbar://refresh"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { ActivityColumn(summary: context.state.claude) }
                DynamicIslandExpandedRegion(.trailing) { ActivityColumn(summary: context.state.codex) }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "資料待更新 · 點此刷新" : "點此開 App 刷新")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(compact(context.state.claude)).font(.caption2).foregroundStyle(.orange)
            } compactTrailing: {
                Text(compact(context.state.codex)).font(.caption2).foregroundStyle(.mint)
            } minimal: {
                Image(systemName: "chart.bar.fill")
            }
            .widgetURL(URL(string: "tokenbar://refresh"))
            .keylineTint(.mint)
        }
    }

    private func compact(_ summary: ActivityProvider) -> String {
        guard let remaining = summary.windows.map(\.remainingPercent).min() else { return "—" }
        return "\(Int(remaining.rounded()))%"
    }
}

private struct ActivityColumn: View {
    let summary: ActivityProvider
    private var accent: Color { summary.provider == .claude ? .orange : .mint }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(summary.provider.title).font(.subheadline.bold()).foregroundStyle(accent)
            ForEach(summary.windows) { window in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(window.label).font(.caption2).lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(Int(window.remainingPercent.rounded()))%")
                        .font(.subheadline.bold()).monospacedDigit()
                    Text("餘").font(.caption2)
                }
                if let reset = window.resetDate {
                    HStack(spacing: 3) {
                        Text("重置").font(.caption2)
                        Text(reset, style: .relative).font(.caption2).monospacedDigit().lineLimit(1)
                    }.foregroundStyle(.secondary)
                }
            }
            if !summary.notice.isEmpty {
                Text(summary.notice + (summary.fetchedAt == nil ? "" : " · 舊資料"))
                    .font(.caption2).foregroundStyle(.orange)
            } else if summary.windows.isEmpty {
                Text("未提供窗口").font(.caption2).foregroundStyle(.secondary)
            }
            if let timestamp = summary.fetchedAt {
                HStack(spacing: 3) {
                    Text("讀取").font(.caption2)
                    Text(Date(timeIntervalSince1970: timestamp), style: .time).font(.caption2)
                }.foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
