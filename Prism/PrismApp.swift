import SwiftUI

@main
struct PrismApp: App {
    @State private var model = AppModel()
    @State private var player = WebPlaybackController()

    var body: some Scene {
        Window("Prism", id: "main") {
            ContentView()
                .environment(model)
                .environment(player)
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
