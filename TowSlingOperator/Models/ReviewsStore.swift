import Foundation
import Combine

/// One customer's verdict on one job.
struct CompanyReview: Decodable, Identifiable, Equatable {
    let stars: Int
    let comment: String?
    let createdAt: String?
    let serviceType: String?
    let area: String?

    /// No id column comes back — reviews are deliberately anonymous, and adding
    /// one would be a handle for pairing a review with the job that produced it.
    /// Composed from the fields instead, which is all SwiftUI needs.
    var id: String { "\(stars)-\(createdAt ?? "")-\(comment?.prefix(24) ?? "")" }

    enum CodingKeys: String, CodingKey {
        case stars, comment, area
        case createdAt   = "created_at"
        case serviceType = "service_type"
    }
}

struct ReviewedCompany: Decodable, Equatable {
    let name: String
    @Flexible var ratingAvg: Double
    let ratingCount: Int
    let jobsCompleted: Int
    let verified: Bool?
    let logoUrl: String?

    enum CodingKeys: String, CodingKey {
        case name, verified
        case ratingAvg      = "rating_avg"
        case ratingCount    = "rating_count"
        case jobsCompleted  = "jobs_completed"
        case logoUrl        = "logo_url"
    }
}

@MainActor
final class ReviewsStore: ObservableObject {

    @Published private(set) var company: ReviewedCompany?
    @Published private(set) var reviews: [CompanyReview] = []
    /// stars (1-5) -> how many, over ALL reviews rather than the page loaded.
    @Published private(set) var breakdown: [Int: Int] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private struct Response: Decodable {
        let company: ReviewedCompany?
        let reviews: [CompanyReview]?
        let breakdown: [String: Int]?
        enum CodingKeys: String, CodingKey { case company, reviews, breakdown }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await API.shared.get("/company/reviews",
                                             query: ["limit": "50"], as: Response.self)
            company = r.company
            reviews = r.reviews ?? []
            // JSON object keys are strings even when they are plainly numbers.
            var b: [Int: Int] = [:]
            for (k, v) in r.breakdown ?? [:] { if let n = Int(k) { b[n] = v } }
            breakdown = b
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not load your reviews."
        }
    }

    /// Only the ones with something written. A star with no words already
    /// counted towards the average and the bars; repeating it as an empty card
    /// pads the list with nothing to read.
    var written: [CompanyReview] {
        reviews.filter { ($0.comment ?? "").isEmpty == false }
    }
}
