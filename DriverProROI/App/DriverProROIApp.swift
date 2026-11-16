import SwiftData
import SwiftUI

@main
struct DriverProROIApp: App {
    init() {
        Store.bootstrap()
        NotificationService.shared.configure()
        ShiftManager.shared.configure(context: Store.container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(Store.container)
    }
}
