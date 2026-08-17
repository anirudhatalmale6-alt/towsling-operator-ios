import SwiftUI
import UIKit

/// The jobs this company is actually running, and the buttons that move them
/// along. This is the screen a driver has open at the roadside.
struct MyJobsView: View {
    @EnvironmentObject private var board: BoardStore

    @State private var busyJobID: Int?
    @State private var actionError: String?
    @State private var completion: BoardStore.CompletionResult?
    /// Set when Complete is pressed on a job still missing photographs.
    @State private var confirmingIncomplete: Job?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    if board.myJobs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "truck.box")
                                .font(.system(size: 30))
                                .foregroundStyle(Theme.inkFaint)
                            Text("No jobs running")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text("Jobs you accept show up here with the buttons to work them.")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.inkFaint)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 46)
                        .cardBackground()
                    } else {
                        ForEach(board.myJobs) { job in
                            LiveJobCard(
                                job: job,
                                busy: busyJobID == job.id,
                                onStatus: { status in advance(job, to: status) },
                                onComplete: { finish(job) }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .refreshable { await board.refresh() }
        }
        .navigationTitle("My jobs")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could not update",
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        // Warn, do not block.
        //
        // Hard-refusing completion without every photograph would strand a
        // driver at 2am on a job he has genuinely finished, and the money with
        // it. He is told exactly what is missing and what it costs him if a
        // claim comes, and then he decides — the server records the gap either
        // way, so the evidence trail is honest about what was and was not taken.
        .alert("Photos are missing",
               isPresented: Binding(get: { confirmingIncomplete != nil },
                                    set: { if !$0 { confirmingIncomplete = nil } })) {
            Button("Take them now", role: .cancel) { confirmingIncomplete = nil }
            Button("Complete anyway", role: .destructive) {
                if let job = confirmingIncomplete {
                    confirmingIncomplete = nil
                    finish(job, force: true)
                }
            }
        } message: {
            Text("Still needed: \(confirmingIncomplete?.photoState?.missingSummary ?? "")."
               + "\n\nWithout them a damage claim on this vehicle is your word "
               + "against the customer's.")
        }
        .alert("Job completed",
               isPresented: Binding(get: { completion != nil },
                                    set: { if !$0 { completion = nil } })) {
            Button("OK", role: .cancel) { completion = nil }
        } message: {
            // The two outcomes are genuinely different and are worded that way.
            // A driver whose customer's card failed has NOT been paid, and being
            // told "completed" with a tick would be the platform's problem
            // dressed up as his success.
            if let c = completion {
                if c.settled {
                    Text("Paid. \(Money.string(c.net ?? 0)) is on its way to your balance.")
                } else {
                    Text("The work is recorded, but the customer's card could not be "
                       + "charged yet. Your payment is pending while we sort it out.")
                }
            }
        }
    }

    private func advance(_ job: Job, to status: String) {
        busyJobID = job.id
        Task {
            let err = await board.setStatus(job, to: status)
            busyJobID = nil
            if let err { actionError = err }
        }
    }

    private func finish(_ job: Job, force: Bool = false) {
        // The checklist rides along on every job the server sends, so this
        // costs no extra request.
        if !force, let photos = job.photoState,
           photos.required == true, photos.complete != true {
            confirmingIncomplete = job
            return
        }
        busyJobID = job.id
        Task {
            let result = await board.complete(job)
            busyJobID = nil
            if result.ok { completion = result }
            else { actionError = result.message }
        }
    }
}

private struct LiveJobCard: View {
    let job: Job
    let busy: Bool
    let onStatus: (String) -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            JobCard(job: job, showAccept: false)

            // The big green "Call the customer" button is gone at Ricardo's
            // request. The number itself is still on the card above — the
            // server sends it once the company owns the job — and iOS makes any
            // phone number in text tappable, so the driver has not lost the
            // ability to ring, only the button.

            if let address = job.pickupAddress, !address.isEmpty {
                Button {
                    openMaps(address)
                } label: {
                    Label(address, systemImage: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, 8)
            }

            // The evidence, reachable from the job itself rather than buried
            // somewhere else — it is taken at the vehicle, with the job open.
            NavigationLink {
                JobPhotosView(jobID: job.id, title: job.callNumber)
            } label: {
                HStack {
                    Label(photoLabel, systemImage: photoComplete ? "checkmark.seal.fill" : "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(photoComplete ? Theme.green : Theme.amber)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .padding(.horizontal, 14)
                .background(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(photoComplete ? Theme.green.opacity(0.4) : Theme.amber.opacity(0.4),
                                lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .padding(.top, 8)

            // One button, whichever one comes next. A row of four with three
            // greyed out is how a driver taps the wrong one in the rain.
            if let next = nextStep {
                Button {
                    if next.status == "completed" { onComplete() } else { onStatus(next.status) }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text(next.label) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
                .padding(.top, 10)
            }
        }
    }

    private var photoComplete: Bool { job.photoState?.complete == true }

    private var photoLabel: String {
        guard let s = job.photoState else { return "Photos" }
        return photoComplete
            ? "Photos — all \(s.totalCount) taken"
            : "Photos — \(s.doneCount) of \(s.totalCount)"
    }

    private var nextStep: (status: String, label: String)? {
        switch job.status {
        case "awarded":     return (status: "en_route", label: "I am on my way")
        case "en_route":    return (status: "on_scene", label: "I have arrived")
        case "on_scene":
            // A lockout or a jump start finishes on scene; there is no towing
            // step to walk through, and offering one would be a dead end.
            // Written as if/else rather than a ternary — Swift will not always
            // infer a labelled tuple through one.
            if job.serviceType == "tow" {
                return (status: "in_progress", label: "Vehicle loaded")
            } else {
                return (status: "completed", label: "Job complete")
            }
        case "in_progress": return (status: "completed", label: "Job complete")
        default:            return nil
        }
    }

    /// Google Maps if it is on the phone, Apple Maps if it is not.
    ///
    /// Drivers navigate on what they know, and for most of them that is Google.
    /// canOpenURL on the comgooglemaps scheme is the only way to ask, and it
    /// needs comgooglemaps in LSApplicationQueriesSchemes — without that entry
    /// iOS answers false no matter what is installed, and the app quietly falls
    /// back to Apple Maps forever with nothing to show why.
    private func openMaps(_ address: String) {
        let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let google = URL(string: "comgooglemaps://?daddr=\(q)&directionsmode=driving"),
           UIApplication.shared.canOpenURL(google) {
            UIApplication.shared.open(google)
            return
        }
        // Apple Maps is always installed, so this always works.
        if let apple = URL(string: "http://maps.apple.com/?daddr=\(q)") {
            UIApplication.shared.open(apple)
        }
    }
}
