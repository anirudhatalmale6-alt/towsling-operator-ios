import SwiftUI
import UIKit

/// The four documents that stand between a company and its first job.
///
/// The important thing this screen does is distinguish "you have not uploaded
/// it" from "you have, and a human has not looked yet". Before the server drew
/// that line, a company that had uploaded everything an hour ago saw the same
/// red warning as one that had uploaded nothing — telling an operator who had
/// done the work that he had not.
struct DocumentsView: View {
    @StateObject private var store = DocsStore()

    @State private var picking: DocChecklistItem?
    @State private var source: Source?
    @State private var expiryFor: DocChecklistItem?
    @State private var expiryText = ""

    enum Source: Identifiable {
        case files(DocChecklistItem)
        case camera(DocChecklistItem)
        var id: String {
            switch self {
            case .files(let i):  return "files:" + i.docType
            case .camera(let i): return "cam:" + i.docType
            }
        }
        var item: DocChecklistItem {
            switch self {
            case .files(let i), .camera(let i): return i
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if store.isLoading && store.checklist.isEmpty {
                        ProgressView().tint(Theme.inkFaint).padding(.vertical, 50)
                    } else {
                        statusCard
                        ForEach(store.checklist) { item in
                            checklistCard(item)
                        }
                        if !store.documents.isEmpty { uploadedCard }
                    }

                    if let message = store.errorMessage {
                        Text(message)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground(padding: 13)
                    }
                    if let note = store.savedNote {
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground(padding: 13)
                    }
                }
                .padding(16)
            }
            .refreshable { await store.load() }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        // Where from — the certificate is usually already a PDF on the phone,
        // but a paper licence on the desk is a photograph.
        .confirmationDialog("Add this document",
                            isPresented: Binding(get: { picking != nil },
                                                 set: { if !$0 { picking = nil } }),
                            titleVisibility: .visible) {
            Button("Choose a file or PDF") {
                if let item = picking { beginUpload(item, .files(item)) }
                picking = nil
            }
            Button("Take a photo of it") {
                if let item = picking { beginUpload(item, .camera(item)) }
                picking = nil
            }
            Button("Cancel", role: .cancel) { picking = nil }
        }
        // Asked BEFORE the file is chosen, because the server rejects an
        // insurance upload without a date and losing the file to a 400 after
        // picking it is the most annoying possible order to do this in.
        .alert("When does it expire?",
               isPresented: Binding(get: { expiryFor != nil },
                                    set: { if !$0 { expiryFor = nil } })) {
            TextField("YYYY-MM-DD", text: $expiryText)
                .keyboardType(.numbersAndPunctuation)
            Button("Continue") {
                if let item = expiryFor { picking = item }
                expiryFor = nil
            }
            Button("Cancel", role: .cancel) { expiryFor = nil; expiryText = "" }
        } message: {
            Text("Insurance certificates are refused without an expiry date, and "
               + "dispatch stops when one lapses.")
        }
        .sheet(item: $source) { src in
            switch src {
            case .files(let item):
                FilePicker(
                    onPick: { data, name, mime in
                        Task {
                            await store.upload(docType: item.docType, data: data,
                                               fileName: name, mimeType: mime,
                                               expiry: expiryText.isEmpty ? nil : expiryText)
                            expiryText = ""
                        }
                    },
                    onFinish: { source = nil }
                )
                .ignoresSafeArea()
            case .camera(let item):
                CameraPicker(
                    source: .camera,
                    onImage: { image in
                        guard let data = image.jobPhotoData() else { return }
                        Task {
                            await store.upload(docType: item.docType, data: data,
                                               fileName: "\(item.docType).jpg",
                                               mimeType: "image/jpeg",
                                               expiry: expiryText.isEmpty ? nil : expiryText)
                            expiryText = ""
                        }
                    },
                    onFinish: { source = nil }
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Cards

    private var statusCard: some View {
        // The DOCUMENTS decide this banner, not the account's verification
        // status. Both a brand-new company and one that has just uploaded its
        // last file are 'pending' on the account, so trusting that told a
        // company with four empty slots that nothing more was needed from it.
        let status = store.docsState ?? store.verificationStatus ?? "missing"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon(status))
                    .foregroundStyle(statusColour(status))
                Text(statusTitle(status))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            Text(statusDetail(status))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = store.rejectionReason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func checklistCard(_ item: DocChecklistItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.uploaded ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 16))
                .foregroundStyle(item.uploaded ? Theme.green : Theme.inkFaint)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(statusWords(item))
                    .font(.system(size: 12))
                    .foregroundStyle(item.status == "rejected" ? Theme.amber : Theme.inkFaint)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if store.uploading == item.docType {
                ProgressView().tint(Theme.inkFaint).scaleEffect(0.8)
            } else {
                Button(item.uploaded ? "Replace" : "Upload") {
                    // Ask for the expiry first where the server needs one.
                    if item.needsExpiry == true {
                        expiryText = ""
                        expiryFor = item
                    } else {
                        picking = item
                    }
                }
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var uploadedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On file")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkDim)

            ForEach(store.documents) { doc in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.label ?? doc.docType)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text([doc.fileName, doc.status.capitalized,
                              doc.expiresAt.map { "expires \($0)" }]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.inkFaint)
                            .lineLimit(2)
                        if let notes = doc.reviewNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    // An approved document is the evidence this account was
                    // vetted, and the server refuses to delete one. No button,
                    // rather than a button that always fails.
                    if doc.status != "approved" {
                        Button("Remove") {
                            Task { await store.delete(doc) }
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Words

    private func beginUpload(_ item: DocChecklistItem, _ src: Source) {
        source = src
    }

    private func statusWords(_ item: DocChecklistItem) -> String {
        switch item.status {
        case "approved": return "Approved" + (item.expiresAt.map { " · expires \($0)" } ?? "")
        case "pending":  return "Uploaded, waiting on review"
        case "rejected": return "Sent back — please upload a new one"
        default:         return "Not uploaded yet"
        }
    }

    private func statusTitle(_ s: String) -> String {
        switch s {
        case "approved": return "Approved"
        case "pending":  return "With us for review"
        case "rejected": return "Something needs redoing"
        case "expired":  return "A certificate has lapsed"
        default:         return "Not submitted yet"
        }
    }

    private func statusDetail(_ s: String) -> String {
        switch s {
        case "approved":
            return "You are cleared to take jobs."
        case "pending":
            return "Everything is in. We check every company before its first job — "
                 + "nothing more is needed from you."
        case "rejected":
            return "Upload a replacement for whatever is flagged below and it goes "
                 + "straight back into the queue."
        case "expired":
            return "An approved certificate has passed its expiry date. Dispatch stops "
                 + "until a current one is uploaded."
        default:
            return "Upload these four and your company goes into the review queue "
                 + "automatically. You do not have to tell anybody."
        }
    }

    private func statusIcon(_ s: String) -> String {
        switch s {
        case "approved": return "checkmark.seal.fill"
        case "pending":  return "clock.fill"
        case "rejected": return "exclamationmark.triangle.fill"
        case "expired":  return "clock.badge.exclamationmark.fill"
        default:         return "tray.and.arrow.up.fill"
        }
    }

    private func statusColour(_ s: String) -> Color {
        switch s {
        case "approved": return Theme.green
        case "pending":  return Theme.accent
        case "rejected": return Theme.amber
        case "expired":  return Theme.red
        default:         return Theme.inkFaint
        }
    }
}
