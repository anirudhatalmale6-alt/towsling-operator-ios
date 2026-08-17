import Foundation
import Combine

/// Totals for the WHOLE filtered set, computed server-side.
///
/// Deliberately not summed from the rows on screen: the list is paged, so
/// adding up what arrived would quietly report the first 50 jobs of a month
/// that had 80 in it — a wrong number that looks entirely right. `jobs` is
/// every job matching the filter; the array's own count is just this page.
struct HistoryTotals: Decodable, Equatable {
    let jobs: Int
    let paidJobs: Int
    let goaJobs: Int
    let canceledJobs: Int
    @Flexible var net: Double
    @Flexible var gross: Double
    @Flexible var fees: Double

    enum CodingKeys: String, CodingKey {
        case jobs
        case paidJobs     = "paid_jobs"
        case goaJobs      = "goa_jobs"
        case canceledJobs = "canceled_jobs"
        case net, gross, fees
    }
}

struct HistoryResponse: Decodable {
    let calls: [Job]
    let count: Int?
    let totals: HistoryTotals?
}

/// Finished work: what was done, and what it paid.
///
/// A separate screen from My jobs on purpose. My jobs is a worklist — short,
/// and every row has a button on it. History is a record, and the questions
/// asked of it ("what did I make this week", "which job was the Silverado on
/// the Turnpike") are nothing like "what do I do next".
@MainActor
final class HistoryStore: ObservableObject {

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var totals: HistoryTotals?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var sessionExpired = false

    /// What the user has typed. The search runs a moment after they stop, not
    /// on every keystroke — a driver typing a plate should not fire eight
    /// requests over a bad connection.
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var range: Range = .month { didSet { Task { await load() } } }
    @Published var kind: Kind = .all      { didSet { Task { await load() } } }

    enum Range: String, CaseIterable, Identifiable {
        case week, month, year, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week:  return "7 days"
            case .month: return "30 days"
            case .year:  return "This year"
            case .all:   return "All time"
            }
        }

        /// Server wants a plain yyyy-MM-dd.
        var from: String? {
            let cal = Calendar.current
            let now = Date()
            let start: Date?
            switch self {
            case .week:  start = cal.date(byAdding: .day, value: -7, to: now)
            case .month: start = cal.date(byAdding: .day, value: -30, to: now)
            case .year:  start = cal.date(from: cal.dateComponents([.year], from: now))
            case .all:   start = nil
            }
            guard let start else { return nil }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: start)
        }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case all, completed, goa, canceled
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:       return "All"
            case .completed: return "Completed"
            case .goa:       return "GOA"
            case .canceled:  return "Cancelled"
            }
        }
        /// `closed` is every finished job, whichever way it ended.
        var statusParam: String {
            self == .all ? "closed" : rawValue
        }
    }

    private var searchTask: Task<Void, Never>?

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        var q: [String: String] = ["status": kind.statusParam, "limit": "100"]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { q["q"] = trimmed }
        if let from = range.from { q["from"] = from }

        do {
            let r = try await API.shared.get("/calls/my-calls", query: q, as: HistoryResponse.self)
            jobs = r.calls
            totals = r.totals
            errorMessage = nil
        } catch let e as APIError {
            if e.isUnauthorized { sessionExpired = true; return }
            errorMessage = e.message
        } catch {
            errorMessage = "Could not load your history."
        }
    }
}
