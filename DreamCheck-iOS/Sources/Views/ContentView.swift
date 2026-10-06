import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今天", systemImage: "bell") }
            StatisticsView()
                .tabItem { Label("统计", systemImage: "chart.bar") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .sheet(item: $model.recordTarget) { target in
            RecordSheet(model: model, eventID: target.id)
        }
    }
}
