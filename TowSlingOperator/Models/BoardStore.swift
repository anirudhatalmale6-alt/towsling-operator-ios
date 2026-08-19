import Foundation
import Combine

/// The available-jobs board and the company's own live jobs.
///
/// Polling rather than sockets, for now. The website uses a websocket with
/// polling underneath it as the floor; the app starts with the floor because it
/// is the part that cannot silently stop. A socket that dies quietly — a proxy
/// idle timeout, a phone changing from LTE to wifi in the yard — leaves a driver
/// staring at a board that has simply frozen, with nothing saying so.
@MainActor
final class BoardStore: ObservableObject {

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var myJobs: [Job] = []
    @Published private(set) var verification: Verification?
    @Published private(set) var isLoading = false
    /// Named errorMessage, NOT error.
    ///
    /// A bare `catch { }` block binds an implicit constant called `error` of
    /// type `any Error`, which shadows a property of that name. Assigning a
    /// String to it then fails twice over — "cannot assign to value: 'error' is
    /// immutable" and "cannot assign value of type 'String' to type 'any
    /// Error'" — and the message points at the assignment rather than at the
    /// name, so it reads as nonsense. Renaming removes the trap for good
    /// instead of leaving it for the next catch block somebody adds.
    @Published var errorMessage: String?

    /// Set when a request comes back 401 so the root view can sign out.
    @Published var sessionExpired = false

    private var timer: Task<Void, Never>?

    // MARK: - Polling

    func start() {
        stop()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(Config.boardRefreshSeconds * 1_000_000_000))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Loading

    func refresh() async {
        // Never two at once. A slow request on bad signal plus a ten second
        // timer is how you end up with the older answer landing last and the
        // board flickering back to a job that is already gone.
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let board = try await API.shared.get("/calls/board", as: BoardResponse.self)
            jobs = board.calls
            verification = board.verification
            errorMessage = nil
        } catch let e as APIError {
            if e.isUnauthorized { sessionExpired = true; return }
            // Keep whatever is on screen. Replacing a list of real jobs with an
            // error because one poll failed is worse than showing them a few
            // seconds stale — the operator can still act on what is there.
            errorMessage = e.message
        } catch {
            errorMessage = "Could not load jobs."
        }

        await refreshMine()
    }

    func refreshMine() async {
        do {
            let mine = try await API.shared.get(
                "/calls/my-calls", query: ["limit": "50"], as: MineResponse.self
            )
            myJobs = mine.calls.filter { $0.isLive }

            // Feed the customer's map. Only ever driven by a SUCCESSFUL fetch:
            // a failed poll must not be read as "the job ended" and shut the
            // tracking down on a driver who is mid-tow with bad signal.
            JobTracker.shared.sync(activeCallID: jobBeingDriven?.id)
        } catch let e as APIError {
            if e.isUnauthorized { sessionExpired = true }
        } catch { }
    }

    /// The job whose customer is watching a map right now.
    ///
    /// A driver can hold more than one — he accepts the next while finishing
    /// this one — so "the first live job" is not good enough. The furthest
    /// along is the one he is actually driving; the others have customers who
    /// have not been given a truck to watch yet.
    private var jobBeingDriven: Job? {
        let rank = ["in_progress": 3, "on_scene": 2, "en_route": 1, "awarded": 0]
        return myJobs.max { (rank[$0.status] ?? -1) < (rank[$1.status] ?? -1) }
    }

    // MARK: - Acting on a job

    /// Take the job. The ETA is what the driver promises the customer, and the
    /// server refuses without it.
    func accept(_ job: Job, etaMinutes: Int) async -> String? {
        struct AcceptResponse: Decodable { }
        do {
            _ = try await API.shared.post(
                "/calls/accept",
                body: ["call_id": job.id, "eta_minutes": etaMinutes],
                as: AcceptResponse.self
            )
            await refresh()
            return nil
        } catch let e as APIError {
            // The commonest failure by far is somebody else getting there
            // first, and the server's own wording says so better than a generic
            // "could not accept" would.
            return e.message
        } catch {
            return "Could not accept the job."
        }
    }

    /// Hand an accepted job back to the board.
    ///
    /// The way out of a job this company can no longer run — a truck that will
    /// not start, an address that turns out to be a vehicle it cannot lift.
    /// Before this the only alternatives were driving a truck that could not go
    /// and leaving a stranded customer watching a countdown for nothing.
    ///
    /// Returns the server's own sentence on success, because it carries the
    /// count: hand back too many in a month and the account gets reviewed, and
    /// the operator should hear that from the button he just pressed.
    func release(_ job: Job, reason: String?) async -> (ok: Bool, message: String) {
        struct ReleaseResponse: Decodable {
            let message: String?
        }
        do {
            let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            var body: [String: Any] = ["call_id": job.id]
            // Sent only when there is something to send. An empty string stored
            // as the reason is worse than NULL — it reads as "he gave a reason"
            // in every report that checks for one.
            if let trimmed, !trimmed.isEmpty { body["reason"] = trimmed }

            let r = try await API.shared.post("/calls/release", body: body, as: ReleaseResponse.self)
            await refresh()
            return (true, r.message ?? "Job handed back.")
        } catch let e as APIError {
            return (false, e.message)
        } catch {
            return (false, "Could not hand the job back.")
        }
    }

    /// Finish the job. A separate endpoint from setStatus, not a fourth status:
    /// completing is what charges the customer's card and creates the payout,
    /// so it goes through its own handler rather than sharing one with "I am on
    /// my way".
    func complete(_ job: Job) async -> CompletionResult {
        do {
            let r = try await API.shared.post(
                "/calls/complete", body: ["call_id": job.id], as: CompleteResponse.self
            )
            await refresh()
            // settled == false means the work is done and counted, but the
            // customer's card could not be charged. The driver is told plainly
            // rather than shown a success tick — his payout is not coming until
            // that is sorted out.
            return CompletionResult(ok: true,
                                    settled: r.settled ?? true,
                                    message: nil,
                                    net: r.netToYou?.wrappedValue)
        } catch let e as APIError {
            return CompletionResult(ok: false, settled: false, message: e.message, net: nil)
        } catch {
            return CompletionResult(ok: false, settled: false,
                                    message: "Could not complete the job.", net: nil)
        }
    }

    struct CompletionResult {
        let ok: Bool
        let settled: Bool
        let message: String?
        let net: Double?
    }

    private struct CompleteResponse: Decodable {
        let settled: Bool?
        let netToYou: Flexible?

        enum CodingKeys: String, CodingKey {
            case settled
            case netToYou = "net_to_you"
        }
    }

    /// Move a job along: en route, on scene, in progress.
    func setStatus(_ job: Job, to status: String) async -> String? {
        struct StatusResponse: Decodable { }
        do {
            _ = try await API.shared.post(
                "/calls/status",
                body: ["call_id": job.id, "status": status],
                as: StatusResponse.self
            )
            await refresh()
            return nil
        } catch let e as APIError {
            return e.message
        } catch {
            return "Could not update the job."
        }
    }
}
