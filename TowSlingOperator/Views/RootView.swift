import SwiftUI

/// Decides which of the three states the app is in: still checking a stored
/// token, signed out, or signed in.
struct RootView: View {
    @EnvironmentObject private var session: Session
    @StateObject private var board = BoardStore()

    var body: some View {
        Group {
            if session.isRestoring {
                ZStack {
                    Theme.bg.ignoresSafeArea()
                    ProgressView().tint(Theme.accent)
                }
            } else if session.isSignedIn {
                SignedInView()
                    .environmentObject(board)
            } else {
                LoginView()
            }
        }
        .task { await session.restore() }
        .onChange(of: board.sessionExpired) { expired in
            // A 401 from any screen. Sign out rather than leaving every tab
            // failing separately with its own error.
            if expired {
                Task { await session.sessionExpired() }
            }
        }
    }
}

struct SignedInView: View {
    @EnvironmentObject private var board: BoardStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.board

    enum Tab: Hashable { case board, mine, money, history, more }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { BoardView() }
                .tabItem { Label("Jobs", systemImage: "list.bullet.rectangle") }
                .tag(Tab.board)

            NavigationStack { MyJobsView() }
                .tabItem { Label("My jobs", systemImage: "truck.box.fill") }
                .badge(board.myJobs.count)
                .tag(Tab.mine)

            NavigationStack { MoneyView() }
                .tabItem { Label("Money", systemImage: "dollarsign.circle.fill") }
                .tag(Tab.money)

            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            NavigationStack { MoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(Tab.more)
        }
        .tint(Theme.accent)
        .onAppear { board.start() }
        .onDisappear { board.stop() }
        .onChange(of: scenePhase) { phase in
            // Stop polling the moment the app goes to the background. iOS will
            // suspend us anyway, but a timer left running burns battery on the
            // way down and fires a request the instant we come back that the
            // refresh below would repeat.
            switch phase {
            case .active:     board.start()
            case .background: board.stop()
            default:          break
            }
        }
    }
}

/// Everything not yet built, plus sign out. Placeholder screens are listed
/// honestly rather than hidden, so it is obvious what is still coming.
struct MoreView: View {
    @EnvironmentObject private var session: Session
    @ObservedObject private var push = PushRegistrar.shared   // owned by the app, not by this view
    @State private var signingOut = false
    @State private var deleting = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if let account = session.account {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.name)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            if let email = session.user?.email {
                                Text(email)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.inkDim)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardBackground()
                    }

                    // Whether alerts are actually on. Silence is the one thing
                    // this app cannot afford to be ambiguous about: an operator
                    // who thinks push is working and is getting nothing simply
                    // concludes there is no work about.
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: push.authorized ? "bell.badge.fill" : "bell.slash.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(push.authorized ? Theme.green : Theme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(push.authorized ? "Job alerts are on" : "Job alerts are off")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(push.authorized
                                 ? "You will get a notification when a job comes up near you."
                                 : "Turn notifications on for TowSling in the Settings app, "
                                 + "or you will only see jobs while the app is open.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                            if let err = push.lastError {
                                Text(err)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Coming in the next builds")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.inkDim)
                        ForEach(["Alerts",
                                 "My rates",
                                 "Documents",
                                 "Company, trucks and equipment",
                                 "Taking-jobs switch",
                                 "Push notifications",
                                 "Live location while on a job"], id: \.self) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "circle.dashed")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.inkFaint)
                                Text(item)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        Text("Everything here already works on the website in the meantime.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkFaint)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()

                    Link("Support", destination: Config.supportURL)
                        .buttonStyle(GhostButtonStyle())

                    Button {
                        signingOut = true
                        Task { await session.signOut(); signingOut = false }
                    } label: {
                        if signingOut { ProgressView().tint(Theme.inkDim) }
                        else { Text("Sign out") }
                    }
                    .buttonStyle(GhostButtonStyle())

                    // Required by Apple for any app that creates accounts, and
                    // it has to be reachable in the app rather than being a link
                    // to a website. Deliberately last, and deliberately not
                    // styled like the buttons above it.
                    Button(role: .destructive) {
                        deleting = true
                    } label: {
                        Text("Delete my account")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .padding(.top, 6)
                }
                .padding(16)
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $deleting) {
            DeleteAccountView().environmentObject(session)
        }
    }
}
