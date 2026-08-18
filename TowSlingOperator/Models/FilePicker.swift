import SwiftUI
import UniformTypeIdentifiers

/// The Files app, for picking a PDF or an image of a document.
///
/// A compliance document is usually a PDF an insurer emailed, which is why this
/// exists alongside the camera: the camera path covers a licence sitting on the
/// desk, this one covers the certificate already on the phone.
///
/// `asCopy: true` matters. Without it the picker hands back a URL into another
/// app's sandbox that has to be opened inside a security scope and can vanish
/// underneath you — reading it later gives an empty file with no error worth
/// showing anybody.
struct FilePicker: UIViewControllerRepresentable {
    let onPick: (Data, String, String) -> Void      // data, filename, mime
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.pdf, .image, .plainText],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: FilePicker
        init(_ parent: FilePicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            defer { parent.onFinish() }
            guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }

            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                     ?? "application/octet-stream"
            parent.onPick(data, url.lastPathComponent, mime)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onFinish()
        }
    }
}
