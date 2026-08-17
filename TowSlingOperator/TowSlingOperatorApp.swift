import SwiftUI
import UIKit

/// Only here to receive the APNs device token.
///
/// SwiftUI has no way to get one — `didRegisterForRemoteNotificationsWithDeviceToken`
/// is a UIApplicationDelegate callback and there is no SwiftUI equivalent, so a
/// delegate is required however little else it does.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushRegistrar.shared.received(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Almost always a missing aps-environment entitlement, which is a build
        // setting problem rather than anything the driver did. Recorded so the
        // Alerts row can say something truthful instead of staying silent.
        Task { @MainActor in PushRegistrar.shared.failed(error) }
    }
}

@main
struct TowSlingOperatorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = Session()

    init() {
        // The dashboard is dark and stays dark. Following the phone's light
        // mode would give us a half-converted screen, and the palette this app
        // borrows from the website has no light variant.
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.panel)
        nav.shadowColor = UIColor(Theme.line)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.ink)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(Theme.panel)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                // Permission is asked once somebody is signed in and looking at
                // jobs — never on the launch screen. iOS allows the prompt
                // exactly once, and a refusal cannot be undone from inside the
                // app.
                .onChange(of: session.isSignedIn) { signedIn in
                    if signedIn {
                        PushRegistrar.shared.signedIn()
                        Task { await PushRegistrar.shared.requestIfNeeded() }
                    } else {
                        PushRegistrar.shared.signedOut()
                    }
                }
        }
    }
}
