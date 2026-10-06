import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationView {
            Form {
                Section("提醒模式") {
                    Picker("模式", selection: modeBinding) {
                        ForEach(ReminderMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.settings.reminderMode == .aligned {
                        Picker("提醒间隔", selection: intervalBinding) {
                            ForEach(ReminderMode.aligned.intervalChoices, id: \.self) { minutes in
                                Text(intervalLabel(minutes)).tag(minutes)
                            }
                        }
                    } else {
                        Stepper(value: intervalBinding, in: 1...120) {
                            HStack {
                                Text("提醒间隔")
                                Spacer()
                                Text(intervalLabel(model.settings.intervalMinutes))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("提醒时间窗") {
                    DatePicker("开始", selection: startMinutesBinding, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: endMinutesBinding, displayedComponents: .hourAndMinute)
                    if model.settings.window.crossesMidnight {
                        Text("结束时间早于开始时间，时间窗将跨越午夜。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("振动强度") {
                    Picker("振动强度", selection: vibrationBinding) {
                        ForEach(VibrationIntensity.allCases) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("开启验梦提醒", isOn: enabledBinding)
                }

                Section(footer: iOSLimitations) {
                    EmptyView()
                }
            }
            .navigationTitle("设置")
        }
        .navigationViewStyle(.stack)
    }

    private var modeBinding: Binding<ReminderMode> {
        Binding(
            get: { model.settings.reminderMode },
            set: { value in model.updateSettings { $0.reminderMode = value } }
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { model.settings.intervalMinutes },
            set: { value in model.updateSettings { $0.intervalMinutes = value } }
        )
    }

    private var vibrationBinding: Binding<VibrationIntensity> {
        Binding(
            get: { model.settings.vibrationIntensity },
            set: { value in model.updateSettings { $0.vibrationIntensity = value } }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.settings.enabled },
            set: { value in model.updateSettings { $0.enabled = value } }
        )
    }

    private var startMinutesBinding: Binding<Date> {
        Binding(
            get: { minutesToDate(model.settings.window.startMinutes) },
            set: { newDate in
                let minutes = dateToMinutes(newDate)
                model.updateSettings { $0.window.startMinutes = minutes }
            }
        )
    }

    private var endMinutesBinding: Binding<Date> {
        Binding(
            get: { minutesToDate(model.settings.window.endExclusiveMinutes) },
            set: { newDate in
                let minutes = dateToMinutes(newDate)
                model.updateSettings { $0.window.endExclusiveMinutes = minutes }
            }
        )
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes >= 60 && minutes % 60 == 0 {
            return "\(minutes / 60) 小时"
        }
        return "\(minutes) 分钟"
    }

    private func minutesToDate(_ minutes: Int) -> Date {
        let hour = minutes / 60
        let minute = minutes % 60
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func dateToMinutes(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private var iOSLimitations: Text {
        Text("iOS 说明：提醒依赖系统通知，最多可排队 64 条，打开应用时会自动补排。无法像安卓那样锁屏全屏弹窗或持续振动；通知在锁屏与横幅中显示。")
    }
}
