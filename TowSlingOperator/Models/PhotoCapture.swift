import SwiftUI
import UIKit
import CoreLocation

/// The camera, wrapped so SwiftUI can present it.
///
/// UIImagePickerController rather than PhotosPicker: this is evidence, and the
/// camera is the default every time, because a photograph taken now at the
/// vehicle is worth something in a dispute and one chosen from a library could
/// be of anything from any day.
///
/// The library is still offered as a second choice rather than hidden. A driver
/// whose camera permission is switched off, one who shot the damage in another
/// app before the job was accepted, and anyone testing on a simulator all need
/// a way in — and the server records WHICH of the two it was, so the difference
/// survives into the record instead of being quietly flattened.
struct CameraPicker: UIViewControllerRepresentable {
    /// `.camera` or `.photoLibrary`. Falls back to the library wherever there
    /// is no camera, which is every simulator.
    var source: UIImagePickerController.SourceType = .camera
    let onImage: (UIImage) -> Void
    /// Called on both paths — picked and cancelled.
    ///
    /// An explicit callback rather than @Environment(\.dismiss) read from the
    /// Coordinator. The Coordinator holds a COPY of this struct, and relying on
    /// an environment value having been injected into that particular copy is
    /// the sort of thing that works until it does not — and the failure is a
    /// camera sheet that will not close, on the screen a driver is standing in
    /// the rain using.
    let onFinish: () -> Void

    static var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Asking for a camera that is not there gives a black sheet with no
        // explanation, so the library is the floor whatever was requested.
        picker.sourceType = (source == .camera && !Self.cameraAvailable)
            ? .photoLibrary : source
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish()
        }
    }
}

extension UIImage {
    /// Down to something sendable from a yard with one bar.
    ///
    /// A modern iPhone shoots around 12 megapixels — four or five megabytes,
    /// seven times over for the required shots. 1600px on the long edge still
    /// resolves a number plate, a VIN plate and a scratch in a door, which is
    /// the entire purpose of these photographs.
    func jobPhotoData() -> Data? {
        let maxEdge = Config.photoMaxEdge
        let longest = max(size.width, size.height)

        // Already small enough. Re-encoding it would only lose quality.
        guard longest > maxEdge else {
            return jpegData(compressionQuality: Config.photoJPEGQuality)
        }

        let scale = maxEdge / longest
        let target = CGSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                    // points == pixels, or a 3x phone triples it again
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: Config.photoJPEGQuality)
    }
}

/// One position, once, for stamping onto a photograph.
///
/// Not a running location feed — this is asked at the moment a picture is
/// taken and then stops. A coordinate on a photo of an empty parking space is
/// what turns "he says the car was gone" into something that stands up in a
/// dispute, and it is the reason a GOA can be paid on a driver's word at all.
@MainActor
final class OneShotLocation: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var waiting: [(CLLocation?) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Returns the current position, or nil. NEVER blocks the upload: a photo
    /// without coordinates is far better than a photo that was not taken
    /// because the phone was in a basement car park with no signal.
    func current() async -> CLLocation? {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        guard status != .denied, status != .restricted else { return nil }

        // A cached fix from the last couple of minutes is good enough to stamp
        // a photograph and costs nothing.
        if let last = manager.location, last.timestamp.timeIntervalSinceNow > -120 {
            return last
        }

        return await withCheckedContinuation { continuation in
            var resumed = false
            waiting.append { location in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: location)
            }
            manager.requestLocation()

            // Do not let a photograph wait on a fix that is not coming.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self?.deliver(nil)
            }
        }
    }

    private func deliver(_ location: CLLocation?) {
        let pending = waiting
        waiting = []
        pending.forEach { $0(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.deliver(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in self.deliver(nil) }
    }
}
