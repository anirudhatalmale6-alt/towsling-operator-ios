import Foundation
import Combine
import UIKit

/// One of the four documents that stand between a company and its first job.
struct DocChecklistItem: Decodable, Identifiable, Equatable {
    let docType: String
    let label: String
    let uploaded: Bool
    let status: String?
    let expiresAt: String?
    let notes: String?
    /// The server decides this, not the app. The upload endpoint refuses these
    /// types without a date, and a second copy of the list in here would go
    /// stale the day the first one changes.
    let needsExpiry: Bool?

    var id: String { docType }

    enum CodingKeys: String, CodingKey {
        case docType     = "doc_type"
        case label, uploaded, status, notes
        case expiresAt   = "expires_at"
        case needsExpiry = "needs_expiry"
    }
}

struct ComplianceDoc: Decodable, Identifiable, Equatable {
    let id: Int
    let docType: String
    let label: String?
    let fileName: String?
    let status: String
    let expiresAt: String?
    let reviewNotes: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, label, status
        case docType     = "doc_type"
        case fileName    = "file_name"
        case expiresAt   = "expires_at"
        case reviewNotes = "review_notes"
        case createdAt   = "created_at"
    }
}

@MainActor
final class DocsStore: ObservableObject {

    @Published private(set) var checklist: [DocChecklistItem] = []
    @Published private(set) var documents: [ComplianceDoc] = []
    @Published private(set) var verificationStatus: String?
    @Published private(set) var rejectionReason: String?
    @Published private(set) var isLoading = false
    @Published private(set) var uploading: String?
    @Published var errorMessage: String?
    @Published var savedNote: String?

    private struct Response: Decodable {
        let checklist: [DocChecklistItem]?
        let documents: [ComplianceDoc]?
        let verificationStatus: String?
        let rejectionReason: String?
        enum CodingKeys: String, CodingKey {
            case checklist, documents
            case verificationStatus = "verification_status"
            case rejectionReason    = "rejection_reason"
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await API.shared.get("/docs/mine", as: Response.self)
            checklist = r.checklist ?? []
            documents = r.documents ?? []
            verificationStatus = r.verificationStatus
            rejectionReason = r.rejectionReason
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not load your documents."
        }
    }

    /// Send one document. `expiry` is "YYYY-MM-DD" and required for the two
    /// types that carry one.
    func upload(docType: String, data: Data, fileName: String,
                mimeType: String, expiry: String?) async {
        uploading = docType
        defer { uploading = nil }

        var fields = ["doc_type": docType]
        if let expiry, !expiry.isEmpty { fields["expires_at"] = expiry }

        struct UploadResponse: Decodable {
            let submittedForReview: Bool?
            enum CodingKeys: String, CodingKey { case submittedForReview = "submitted_for_review" }
        }

        do {
            let r = try await API.shared.upload("/docs/upload",
                                                fields: fields,
                                                fileName: fileName,
                                                mimeType: mimeType,
                                                fileData: data,
                                                as: UploadResponse.self)
            // The one thing worth interrupting for. Finishing the set is what
            // moves the account into the review queue, and an operator who is
            // not told that keeps checking a screen that will not change until
            // a human looks at it.
            savedNote = r.submittedForReview == true
                ? "That was the last one — your company is now with us for review."
                : "Uploaded."
            errorMessage = nil
            await load()
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "That document did not upload. Try again."
        }
    }

    func delete(_ doc: ComplianceDoc) async {
        do {
            try await API.shared.postIgnoringResult("/docs/delete", body: ["id": doc.id])
            savedNote = "Removed."
            errorMessage = nil
            await load()
        } catch let e as APIError {
            // An approved document is deliberately locked — it is the evidence
            // the account was vetted. The server says so; do not paper over it.
            errorMessage = e.message
        } catch {
            errorMessage = "Could not remove that document."
        }
    }
}
