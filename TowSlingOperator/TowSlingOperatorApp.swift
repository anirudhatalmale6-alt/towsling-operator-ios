import SwiftUI
import UIKit

@main
struct TowSlingOperatorApp: App {
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
        }
    }
}
