import SwiftUI
import AppIntents

/// Keep the lock-screen presentation within iOS's 160-point height budget.
struct QuotaCardView: View {
    let content: QuotaActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                QuotaCardColumn(summary: content.claude)
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                QuotaCardColumn(summary: content.codex)
            }
            .frame(height: 96)
            // Keep the action available even if a previous background process was
            // terminated. QuotaStore enforces cooldowns and deduplicates requests.
            Button(intent: RefreshQuotaIntent()) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.clockwise")
                        Text(isStale ? "資料待更新 · 更新額度" : "更新剩餘額度")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(red: 0.15, green: 0.24, blue: 0.23), in: RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(Color(red: 0.65, green: 0.95, blue: 0.90))
                    .contentShape(RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityHint("在背景嘗試查詢；需要驗證時請點卡片開啟 App")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(height: 160).foregroundStyle(.white)
        .dynamicTypeSize(.medium)
    }
}

struct QuotaCardColumn: View {
    let summary: ActivityProvider
    private var accent: Color { summary.provider == .claude ? .orange : .mint }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(summary.provider == .claude ? "ClaudeMark" : "OpenAIMark")
                    .resizable().scaledToFit().frame(width: 17, height: 17).accessibilityHidden(true)
                Text(summary.provider.title).font(.system(size: 13, weight: .semibold))
                if !summary.planLabel.isEmpty {
                    Text(summary.planLabel).font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }.frame(height: 18)
            ForEach(Array(summary.windows.prefix(2))) { window in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(window.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                        Spacer(minLength: 2)
                        Text("\(Int(window.remainingPercent.rounded()))%")
                            .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    }.frame(height: 16)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(accent).frame(width: geometry.size.width * window.remainingPercent / 100)
                        }
                    }.frame(height: 4)
                    .accessibilityLabel("\(window.label)剩餘 \(Int(window.remainingPercent.rounded()))%")
                    HStack(spacing: 2) {
                        if !summary.notice.isEmpty {
                            Text(summary.notice + " · 點卡片").foregroundStyle(.orange)
                        } else if let reset = window.resetDate {
                            Text("重置")
                            if reset <= Date() { Text("待確認") }
                            else { Text(reset, style: .relative).monospacedDigit() }
                        } else { Text("未提供重置時間") }
                    }
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1).minimumScaleFactor(0.85).frame(height: 13)
                }
            }
            if summary.windows.isEmpty {
                Text(summary.notice.isEmpty ? "未提供額度" : summary.notice)
                    .font(.system(size: 11)).foregroundStyle(.orange)
                if summary.notice != "尚未連接" {
                    Text("點卡片開 App 處理").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
