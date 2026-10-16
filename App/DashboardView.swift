import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var loginProvider: Provider?
    @State private var disconnectProvider: Provider?
    @State private var showingHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("額度一眼看").font(.largeTitle.bold())
                            Text("手機直接查詢 · 顯示剩餘百分比")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { await store.refreshAll() } } label: {
                            Image(systemName: "arrow.clockwise").font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("刷新全部額度")
                    }

                    ForEach(Provider.allCases) { provider in
                        ProviderCard(provider: provider, state: store.states[provider]!,
                            selectedOrganization: store.organizationID,
                            onLogin: {
                                store.beginLogin(provider)
                                loginProvider = provider
                            },
                            onRefresh: { Task { await store.refresh(provider) } },
                            onDisconnect: { disconnectProvider = provider },
                            onOrganization: { id in Task { await store.selectOrganization(id) } })
                    }

                    ActivityControls(controller: store.activities, store: store)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("免費側載續簽備忘", systemImage: "calendar.badge.clock")
                            .font(.subheadline.bold())
                        Text("下次記得續簽：\(store.signingReminder.addingTimeInterval(6 * 86400).formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                        Text("這是你手動標記的提醒日期，不是憑證狀態。請在七天到期前用 AltStore 續簽。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("我剛完成續簽") { store.markRenewed() }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))

                    Button("登入、刷新與卡片說明", systemImage: "questionmark.circle") {
                        showingHelp = true
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(20)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.085))
            .refreshable { await store.refreshAll() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $loginProvider) { provider in
                LoginView(session: store.sessions[provider]!) {
                    Task { await store.connect(provider) }
                }
            }
            .sheet(isPresented: $showingHelp) { HelpView() }
            .confirmationDialog("登出並清除這個服務在手機上的登入資料？",
                isPresented: Binding(get: { disconnectProvider != nil }, set: { if !$0 { disconnectProvider = nil } }),
                titleVisibility: .visible) {
                if let provider = disconnectProvider {
                    Button("登出 \(provider.title)", role: .destructive) {
                        Task { await store.disconnect(provider) }
                        disconnectProvider = nil
                    }
                }
            }
            .task {
                await store.refreshAll(automatic: true)
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
                    if scenePhase == .active && loginProvider == nil {
                        await store.refreshAll(automatic: true)
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && loginProvider == nil {
                    store.activities.synchronize()
                    Task { await store.refreshAll(automatic: true) }
                }
            }
        }
        .tint(.mint)
    }
}

private struct ProviderCard: View {
    let provider: Provider
    let state: ProviderState
    let selectedOrganization: String?
    let onLogin: () -> Void
    let onRefresh: () -> Void
    let onDisconnect: () -> Void
    let onOrganization: (String) -> Void
    private var accent: Color { provider == .claude ? .orange : .mint }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 6, height: 28)
                Text(provider.title).font(.title2.bold())
                if let plan = state.snapshot?.plan, !plan.isEmpty {
                    Text(plan.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                }
                Spacer()
                if state.isRefreshing { ProgressView().accessibilityLabel("正在刷新") }
                Menu {
                    Button("登入／開啟官方用量頁", action: onLogin)
                        .disabled(state.isRefreshing)
                    if state.enabled { Button("登出並清除資料", role: .destructive, action: onDisconnect) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("\(provider.title) 帳號設定")
            }

            if provider == .claude && !state.organizations.isEmpty {
                Menu {
                    ForEach(state.organizations) { org in
                        Button {
                            onOrganization(org.id)
                        } label: {
                            if org.id == selectedOrganization {
                                Label("\(org.name) · \(org.id.prefix(6))", systemImage: "checkmark")
                            } else {
                                Text("\(org.name) · \(org.id.prefix(6))")
                            }
                        }
                    }
                } label: {
                    Label(state.snapshot?.accountLabel.isEmpty == false ? state.snapshot!.accountLabel : "選擇團隊或個人空間",
                          systemImage: "person.2")
                        .font(.subheadline).frame(minHeight: 44).multilineTextAlignment(.leading)
                }
            }

            if let snapshot = state.snapshot {
                if snapshot.windows.isEmpty {
                    Text("此帳號未回傳可顯示的額度窗口。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(snapshot.windows) { window in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(window.label).font(.subheadline)
                            Spacer()
                            Text("\(window.remainingPercent.formatted(.number.precision(.fractionLength(0...1))))%")
                                .font(.title2.weight(.semibold)).monospacedDigit()
                            Text("剩餘").font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: window.remainingPercent, total: 100)
                            .tint(window.remainingPercent <= 10 ? .red : accent)
                        if let reset = window.resetDate {
                            Text("預定重置 \(reset.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("未提供重置時間").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("讀取於 \(snapshot.fetchedDate.formatted(date: .omitted, time: .standard))")
                            .foregroundStyle(.secondary)
                        if snapshot.isStale(at: context.date) {
                            Text("資料已過期或已到重置時間，請刷新確認。")
                                .foregroundStyle(.orange)
                        }
                    }.font(.caption)
                }
            } else if !state.enabled {
                Text("登入後，直接從手機讀取訂閱額度。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if let error = state.error, state.enabled {
                Label(error.message + (state.snapshot != nil ? "；上方為上次資料。" : ""), systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let canRefresh = state.canRefresh(at: context.date, automatic: false)
                HStack {
                    Button(state.enabled ? "重新登入" : "連接 \(provider.title)", action: onLogin)
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        .disabled(state.isRefreshing)
                    Spacer()
                    if state.enabled {
                        Button(action: onRefresh) {
                            if state.isRefreshing {
                                Text("刷新中")
                            } else if context.date < state.nextAllowedRefresh {
                                Text("稍候 \(Int(ceil(state.nextAllowedRefresh.timeIntervalSince(context.date)))) 秒")
                            } else {
                                Label("刷新", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderedProminent).disabled(!canRefresh)
                        .frame(minHeight: 44)
                    }
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(0.18)))
    }
}

private struct ActivityControls: View {
    @ObservedObject var controller: ActivityController
    @ObservedObject var store: QuotaStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("鎖定畫面額度卡片", systemImage: "rectangle.bottomthird.inset.filled")
                .font(.headline)
            Text("點卡片即可開 App 刷新。單次最多八小時；背景期間顯示的是最後一次讀取的數字。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(controller.isActive ? "重新開啟八小時卡片" : "開啟額度卡片") {
                    Task { await store.startActivity() }
                }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .disabled(controller.isTransitioning)
                if controller.isActive {
                    Button("停止") { Task { await controller.stop() } }
                        .frame(minHeight: 44)
                }
            }
            if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }
}
