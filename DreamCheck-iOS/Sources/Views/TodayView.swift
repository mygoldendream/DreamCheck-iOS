import Foundation
import SwiftUI
import UserNotifications

struct TodayView: View {
    @EnvironmentObject var model: AppModel

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationView {
            List {
                if model.authorizationStatus != .authorized {
                    Section {
                        permissionBanner
                    }
                }

                Section {
                    Toggle("开启验梦提醒", isOn: enabledBinding)
                }

                Section("今日进度") {
                    let stats = model.dailyStatistics
                    HStack {
                        VStack(alignment: .leading) {
                            Text("完成").font(.caption).foregroundColor(.secondary)
                            Text("\(stats.success)").font(.title.bold())
                        }
                        Spacer()
                        VStack(alignment: .center) {
                            Text("提醒").font(.caption).foregroundColor(.secondary)
                            Text("\(stats.total)").font(.title.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("有效率").font(.caption).foregroundColor(.secondary)
                            Text(rateText(stats.successRate)).font(.title.bold())
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("下一次提醒") {
                    if let next = model.nextScheduledAt {
                        HStack {
                            Text("时间")
                            Spacer()
                            Text(Self.timeFormatter.string(from: next))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("提醒未开启，或今天的时间窗已结束")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button {
                        model.fireTestReminder()
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text("立即测试提醒")
                        }
                    }
                } footer: {
                    Text("测试通知约 1 秒后到达；点“完成了”会记入今天的统计。")
                }
            }
            .navigationTitle("此刻真实吗")
            .onAppear {
                model.refreshAuthorizationStatus()
                model.refreshSchedule()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.settings.enabled },
            set: { value in model.updateSettings { $0.enabled = value } }
        )
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通知权限未开启")
                .font(.headline)
            Text("iOS 依靠系统通知在后台提醒你验梦。请允许通知，否则提醒不会送达。")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("打开设置") {
                model.openSystemSettings()
            }
        }
        .padding(.vertical, 4)
    }

    private func rateText(_ rate: Double) -> String {
        String(format: "%.0f%%", rate * 100)
    }
}
