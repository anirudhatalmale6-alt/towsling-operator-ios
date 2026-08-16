import Foundation

/// Everything environment-specific, in one place.
///
/// The app talks to exactly the same API the website does. There is no separate
/// mobile backend and no second copy of the business rules — pricing, the
/// capability gate, who may accept a job, all of it stays on the server. The app
/// is a client, and that is deliberate: two implementations of "can this company
/// take this job" would disagree within a fortnight.
enum Config {

    static let apiBase = URL(string: "https://towsling.com/api")!

    /// Where "Terms" and "Support" send people. Same pages the site uses.
    static let termsURL   = URL(string: "https://towsling.com/terms?doc=tower")!
    static let supportURL = URL(string: "https://towsling.com/support")!

    /// How often the board refreshes while it is on screen.
    ///
    /// The web dashboard polls every few seconds because a browser tab is
    /// usually one of many. A phone in a driver's hand is the opposite: the
    /// screen is either in front of him or the app is suspended and polling
    /// nothing at all. Ten seconds is frequent enough that a job never feels
    /// stale, without waking the radio for nothing on a truck with poor signal.
    static let boardRefreshSeconds: TimeInterval = 10

    /// Requests give up rather than hang. A driver on one bar of LTE under an
    /// overpass needs to be told the network is bad, not shown a spinner.
    static let requestTimeout: TimeInterval = 20
}
