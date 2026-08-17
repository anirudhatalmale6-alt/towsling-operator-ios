import SwiftUI
import UIKit

/// The evidence for one job: four corners, plate, VIN, and the drop-off.
///
/// This is what a damage claim is answered with. A customer who says a wheel
/// arch was straight when the truck arrived is arguing with a photograph taken
/// at that kerb, at that minute, from that phone — or with nothing at all.
struct JobPhotosView: View {
    let jobID: Int
    let title: String
    /// Shown on a live job, hidden when looking back through history.
    var canCapture: Bool = true

    @StateObject private var store = PhotoStore()
    @State private var capturing: String?
    @State private var viewing: Photo?

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if let message = store.errorMessage {
                        Text(message)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground(padding: 13)
                    }

                    if let s = store.state { progress(s) }

                    if let items = store.state?.items {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(items) { item in
                                SlotTile(item: item,
                                         uploading: store.uploading == item.key,
                                         canCapture: canCapture) {
                                    capturing = item.key
                                }
                            }
                        }
                    }

                    if !store.photos.isEmpty { taken }
                }
                .padding(16)
            }
            .refreshable { await store.load(jobID: jobID) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(jobID: jobID) }
        .sheet(isPresented: Binding(get: { capturing != nil },
                                    set: { if !$0 { capturing = nil } })) {
            if let type = capturing {
                CameraPicker(
                    onImage: { image in
                        Task { await store.upload(jobID: jobID, type: type, image: image) }
                    },
                    onFinish: { capturing = nil }
                )
                .ignoresSafeArea()
            }
        }
        .sheet(item: $viewing) { photo in
            PhotoViewer(photo: photo)
        }
    }

    private func progress(_ s: PhotoState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(s.doneCount) of \(s.totalCount) taken")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if s.complete == true {
                    Label("Complete", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.green)
                }
            }

            ProgressView(value: Double(s.doneCount),
                         total: Double(max(s.totalCount, 1)))
                .tint(s.complete == true ? Theme.green : Theme.accent)

            if let missing = s.missingSummary, !missing.isEmpty {
                // Named, not counted. "3 missing" sends a driver hunting; the
                // list tells him to walk round to the offside rear.
                Text("Still needed: \(missing)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Every required photo is on this job.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var taken: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos on this job")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkDim)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(store.photos) { photo in
                    Button {
                        viewing = photo
                    } label: {
                        VStack(spacing: 4) {
                            AuthedImage(photoID: photo.id)
                                .frame(height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(photo.label ?? photo.photoType)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.inkFaint)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

private struct SlotTile: View {
    let item: PhotoState.Item
    let uploading: Bool
    let canCapture: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if canCapture { onTap() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "camera.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(item.done ? Theme.green : Theme.accent)
                    Spacer()
                    if uploading {
                        ProgressView().tint(Theme.inkFaint).scaleEffect(0.7)
                    }
                }
                Text(item.label)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if let hint = item.hint, !item.done {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if item.done && canCapture {
                    Text("Tap to retake")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(Theme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(item.done ? Theme.green.opacity(0.5) : Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(uploading || !canCapture)
    }
}

/// A photo from the authenticated endpoint.
///
/// Its own view because AsyncImage cannot carry the Authorization header these
/// need, and loading them without one gets a 403 rendered as a broken tile.
struct AuthedImage: View {
    let photoID: Int

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.panel
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.inkFaint)
            } else {
                ProgressView().tint(Theme.inkFaint).scaleEffect(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: photoID) {
            do {
                let data = try await API.shared.data("/calls/photo",
                                                     query: ["id": String(photoID)])
                image = UIImage(data: data)
                failed = (image == nil)
            } catch {
                failed = true
            }
        }
    }
}

private struct PhotoViewer: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                AuthedImage(photoID: photo.id)
                    .aspectRatio(contentMode: .fit)

                VStack(spacing: 2) {
                    Text(photo.label ?? photo.photoType)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(TowDate.short(photo.takenAt))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Button("Close") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.horizontal, 40)
            }
            .padding()
        }
    }
}
