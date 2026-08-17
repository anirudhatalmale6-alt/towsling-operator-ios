import Foundation
import Combine
import UIKit

/// The photo checklist for one job, and the uploads that fill it in.
@MainActor
final class PhotoStore: ObservableObject {

    @Published private(set) var state: PhotoState?
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var isLoading = false
    /// Which slot is mid-upload, so only that tile shows a spinner.
    @Published private(set) var uploading: String?
    @Published var errorMessage: String?

    private let location = OneShotLocation()

    private struct Detail: Decodable {
        let photoState: PhotoState?
        let photos: [Photo]?

        enum CodingKeys: String, CodingKey {
            case photoState = "photo_state"
            case photos
        }
    }

    func load(jobID: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let d = try await API.shared.get("/calls/detail",
                                             query: ["id": String(jobID)],
                                             as: Detail.self)
            state = d.photoState
            photos = d.photos ?? []
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not load the photos."
        }
    }

    /// Send one photograph, stamped with where it was taken.
    ///
    /// The coordinates are attached where they can be got and simply left off
    /// where they cannot. Refusing to upload without a fix would mean a driver
    /// in an underground car park — exactly where the awkward jobs are — cannot
    /// record anything at all, and no evidence is far worse than evidence with
    /// one field missing. The server stamps the IP and the time regardless.
    func upload(jobID: Int, type: String, image: UIImage) async {
        guard let data = image.jobPhotoData() else {
            errorMessage = "That photo could not be prepared for sending."
            return
        }

        uploading = type
        defer { uploading = nil }

        var fields = ["call_id": String(jobID), "photo_type": type]
        if let fix = await location.current() {
            fields["lat"] = String(fix.coordinate.latitude)
            fields["lng"] = String(fix.coordinate.longitude)
            fields["accuracy_m"] = String(Int(fix.horizontalAccuracy.rounded()))
        }

        struct UploadResponse: Decodable {
            let photos: PhotoState?
        }

        do {
            let r = try await API.shared.upload(
                "/calls/photo",
                fields: fields,
                fileName: "\(type).jpg",
                mimeType: "image/jpeg",
                fileData: data,
                as: UploadResponse.self
            )
            // The server sends the new checklist back with the upload, so the
            // tile ticks over without a second round trip.
            if let s = r.photos { state = s }
            await load(jobID: jobID)
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "That photo did not upload. Try again."
        }
    }
}
