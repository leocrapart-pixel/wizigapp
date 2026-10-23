import SwiftUI
import Wizig

@main
struct WizigAppApp: App {
    @State private var message: String = "Loading runtime..."
    private let runtime = WizigRuntime(appName: "WizigApp")
    private let api = try? WizigGeneratedApi()

    var body: some Scene {
        WindowGroup {
            ContentView(message: message, runtimeAvailable: runtime.isAvailable)
                .task {
                    guard let api else {
                        message = "Wizig runtime unavailable"
                        return
                    }
                    message = (try? api.echo("hello")) ?? "Wizig runtime unavailable"
                }
        }
    }
}
