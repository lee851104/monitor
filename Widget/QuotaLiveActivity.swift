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
            QuotaCardView(content: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(red: 0.067, green: 0.098, blue: 0.133))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "tokenbar://refresh"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { QuotaCardColumn(summary: context.state.claude) }
                DynamicIslandExpandedRegion(.trailing) { QuotaCardColumn(summary: context.state.codex) }
                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: RefreshQuotaIntent()) {
                        Label(context.isStale ? "資料待更新 · 更新額度" : "更新剩餘額度", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.tint(.mint)
                }
            } compactLeading: {
                Text(compact(context.state.claude)).font(.caption2).foregroundStyle(.orange)
            } compactTrailing: {
                Text(compact(context.state.codex)).font(.caption2).foregroundStyle(.mint)
            } minimal: { Image(systemName: "chart.bar.fill") }
            .widgetURL(URL(string: "tokenbar://refresh")).keylineTint(.mint)
        }
    }

    private func compact(_ summary: ActivityProvider) -> String {
        guard let remaining = summary.windows.map(\.remainingPercent).min() else { return "—" }
        return "\(Int(remaining.rounded()))%"
    }
}
