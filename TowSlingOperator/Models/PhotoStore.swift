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

    /// The envelope. /calls/detail replies
    /// `{"success":true,"call":{…,"photo_state":{…}}}` — everything is nested
    /// under "call", unlike /calls/board and /calls/my-calls which put their
    /// list at the top level.
    ///
    /// Reading photo_state from the top level here decoded PERFECTLY and gave
    /// nil, because both fields are optional: no error, no message, just a
    /// photo screen with nothing on it and no way in. Optionals turn a
    /// wrong-shaped response into a successful decode of nothing, which is a
    /// far worse failure than a thrown error would have been.
    private struct Response: Decodable {
        let call: Detail?
    }

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
            let r = try await API.shared.get("/calls/detail",
                                             query: ["id": String(jobID)],
                                             as: Response.self)
            // Say so rather than showing an empty screen. If the checklist is
            // ever missing again, the driver is told instead of being left
            // looking at a blank page wondering where the camera went.
            guard let checklist = r.call?.photoState else {
                state = nil
                photos = r.call?.photos ?? []
                errorMessage = "Could not read the photo checklist for this job."
                return
            }
            state = checklist
            photos = r.call?.photos ?? []
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
    func upload(jobID: Int, type: String, image: UIImage,
                source: String = "camera") async {
        guard let data = image.jobPhotoData() else {
            errorMessage = "That photo could not be prepared for sending."
            return
        }

        uploading = type
        defer { uploading = nil }

        // Camera or library, recorded rather than assumed. A photo chosen from
        // the library carries no promise about when or where it was taken, and
        // a record that cannot tell the two apart is worth less than one that
        // admits which it has.
        var fields = ["call_id": String(jobID), "photo_type": type, "source": source]
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
