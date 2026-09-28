import SendKit
import SendKitUI
import SwiftUI

@main
struct ShareToAnythingApp: App {
    @State private var store = EndpointStore(syncsWithICloud: true)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EndpointListView()
                .environment(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reload() }
                }
        }
    }
}
