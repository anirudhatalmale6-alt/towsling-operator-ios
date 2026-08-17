import Foundation
import CoreGraphics   // CGFloat

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

    /// Photographs get much longer than an ordinary request. Twenty seconds is
    /// right for a JSON call and wrong for a 1.5MB upload from a yard with one
    /// bar — the driver would be told the network failed while it was working.
    static let uploadTimeout: TimeInterval = 90

    /// Longest edge, in pixels, that a job photo is resized to before upload.
    ///
    /// A modern iPhone shoots around 12 megapixels — four or five megabytes,
    /// times seven required shots, on truck-stop wifi. 1600px still resolves a
    /// number plate, a VIN plate and a scratch in a door, which is the entire
    /// purpose of these pictures.
    static let photoMaxEdge: CGFloat = 1600
    static let photoJPEGQuality: CGFloat = 0.8
}
