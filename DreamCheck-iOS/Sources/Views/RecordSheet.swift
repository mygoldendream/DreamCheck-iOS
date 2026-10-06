import Foundation
import SwiftUI

struct RecordSheet: View {
    @ObservedObject var model: AppModel
    let eventID: String

    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""
    @State private var loaded = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationView {
            Form {
                if let event = model.event(id: eventID) {
                    Section("这次提醒") {
                        if let message = model.message(for: event) {
                            Text(message.title).font(.headline)
                            Text(message.body)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text("时间 " + Self.timeFormatter.string(from: event.scheduledAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("记录") {
                    TextEditor(text: $note)
                        .frame(minHeight: 110)
                }

                Section {
                    Button {
                        model.saveRecord(eventID: eventID, note: note)
                        dismiss()
                    } label: {
                        Text("完成并保存")
                    }

                    Button(role: .destructive) {
                        model.skipRecord(eventID: eventID)
                        dismiss()
                    } label: {
                        Text("跳过这次")
                    }
                } footer: {
                    Text("「完成并保存」会计入今天的完成次数；「跳过这次」只记一次跳过，不算完成。")
                }
            }
            .navigationTitle("验梦记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            guard !loaded else { return }
            note = model.event(id: eventID)?.note ?? ""
            loaded = true
        }
    }
}
