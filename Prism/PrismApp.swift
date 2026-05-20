import SwiftUI

@main
struct PrismApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Prism", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 920, minHeight: 580)
        }
        .defaultSize(width: 1100, height: 740)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
