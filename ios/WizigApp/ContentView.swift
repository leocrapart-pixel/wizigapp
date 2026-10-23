import SwiftUI

struct ContentView: View {
    let message: String
    let runtimeAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WizigApp")
                .font(.title2.bold())
            Text("Runtime available: \(runtimeAvailable ? "yes" : "no")")
                .foregroundStyle(.secondary)
            Text("Wizig runtime response")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

#Preview {
    ContentView(message: "Preview", runtimeAvailable: true)
}
