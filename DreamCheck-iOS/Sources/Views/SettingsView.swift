import Foundation
import SwiftUI

private func clockText(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

private func intervalText(_ minutes: Int) -> String {
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

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("启用分时段间隔", isOn: useSegmentsBinding)

                    if model.settings.useSegments {
                        ForEach(model.settings.segments) { segment in
                            NavigationLink(destination: SegmentEditorView(segmentID: segment.id)) {
                                segmentRow(segment)
                            }
                        }
                        .onDelete { offsets in
                            model.deleteSegments(at: offsets)
                        }

                        Button {
                            model.addSegment()
                        } label: {
                            Label("添加时段", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("分时段间隔")
                } footer: {
                    Text("开启后每个时段用自己的间隔，比如上午 15 分钟、下午 30 分钟。开启分时段时，下面的「提醒模式」和「提醒时间窗」不再生效。左滑可以删除时段。")
                }

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
                                Text(intervalText(minutes)).tag(minutes)
                            }
                        }
                    } else {
                        Stepper(value: intervalBinding, in: 1...120) {
                            HStack {
                                Text("提醒间隔")
                                Spacer()
                                Text(intervalText(model.settings.intervalMinutes))
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

    private func segmentRow(_ segment: ScheduleSegment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(clockText(segment.startMinutes)) – \(clockText(segment.endExclusiveMinutes))")
                Text("每 \(intervalText(segment.intervalMinutes))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !segment.enabled {
                Text("已关闭")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var useSegmentsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.useSegments },
            set: { value in model.setUseSegments(value) }
        )
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

    private var iOSLimitations: Text {
        Text("iOS 说明：提醒依赖系统通知，最多可排队 64 条，打开应用时会自动补排。无法像安卓那样锁屏全屏弹窗或持续振动；通知在锁屏与横幅中显示。")
    }
}

struct SegmentEditorView: View {
    @EnvironmentObject var model: AppModel
    let segmentID: String

    var body: some View {
        Form {
            if let segment = segment {
                Section("时段") {
                    DatePicker("开始", selection: startBinding(segment), displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: endBinding(segment), displayedComponents: .hourAndMinute)
                    if segment.crossesMidnight {
                        Text("结束时间早于开始时间，这个时段会跨越午夜。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("间隔") {
                    Picker("间隔", selection: intervalBinding(segment)) {
                        ForEach(ReminderMode.continuous.intervalChoices, id: \.self) { minutes in
                            Text(intervalText(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section {
                    Toggle("启用这个时段", isOn: enabledBinding(segment))
                }
            } else {
                Text("这个时段已被删除。")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("编辑时段")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var segment: ScheduleSegment? {
        model.settings.segments.first { $0.id == segmentID }
    }

    private func startBinding(_ segment: ScheduleSegment) -> Binding<Date> {
        Binding(
            get: { minutesToDate(segment.startMinutes) },
            set: { newDate in
                let minutes = dateToMinutes(newDate)
                model.updateSegment(id: segmentID) { $0.startMinutes = minutes }
            }
        )
    }

    private func endBinding(_ segment: ScheduleSegment) -> Binding<Date> {
        Binding(
            get: { minutesToDate(segment.endExclusiveMinutes) },
            set: { newDate in
                let minutes = dateToMinutes(newDate)
                model.updateSegment(id: segmentID) { $0.endExclusiveMinutes = minutes }
            }
        )
    }

    private func intervalBinding(_ segment: ScheduleSegment) -> Binding<Int> {
        Binding(
            get: { segment.intervalMinutes },
            set: { value in
                model.updateSegment(id: segmentID) { $0.intervalMinutes = value }
            }
        )
    }

    private func enabledBinding(_ segment: ScheduleSegment) -> Binding<Bool> {
        Binding(
            get: { segment.enabled },
            set: { value in
                model.updateSegment(id: segmentID) { $0.enabled = value }
            }
        )
    }
}
