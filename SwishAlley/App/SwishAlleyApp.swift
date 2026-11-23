import SwiftUI

@main
struct SwishAlleyApp: App {
    @StateObject private var engine = Engine()
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onReceive(store.$pro) { engine.pro = $0 }
                .task {
                    if ShotsTour.active { await ShotsTour(engine: engine).run() }
                }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active: engine.activate()
            case .background: engine.deactivate()
            default: break
            }
        }
    }
}
