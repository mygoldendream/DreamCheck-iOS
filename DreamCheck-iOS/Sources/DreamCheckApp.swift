import SwiftUI

@main
struct DreamCheckApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task {
                    await model.requestAuthorization()
                    model.refreshSchedule()
                }
        }
    }
}
