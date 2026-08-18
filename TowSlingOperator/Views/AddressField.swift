import SwiftUI

/// A yard address, typed with suggestions, resolved to a real position.
///
/// Typing an address is not the point — the COORDINATES are. Every job this
/// company is offered is measured from that point when no phone has reported
/// recently, so an address that never got looked up leaves the company matched
/// from the middle of its state.
///
/// So this insists on the round trip: pick a suggestion, and the server
/// geocodes it and hands back lat/lng plus a tidied city, state and ZIP. Free
/// text is still allowed — an operator whose yard is a gate on a dirt road
/// should not be locked out of the form — but the screen says plainly that it
/// has no position until one is chosen.
struct AddressField: View {
    @Binding var text: String
    /// Called when a suggestion resolves. Everything is optional because the
    /// geocoder returns what it is confident about and nothing more.
    let onResolved: (Resolved) -> Void

    struct Resolved {
        let address: String
        let lat: Double
        let lng: Double
        let city: String?
        let state: String?
        let zip: String?
    }

    @State private var suggestions: [String] = []
    @State private var searching = false
    @State private var resolving = false
    @State private var errorMessage: String?
    /// Suppresses the lookup that would otherwise fire from setting `text`
    /// after a suggestion is tapped — which would reopen the list underneath
    /// the address just chosen.
    @State private var justPicked = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Street address", text: $text)
                    .textContentType(.fullStreetAddress)
                    .autocorrectionDisabled()
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                if searching || resolving {
                    ProgressView().tint(Theme.inkFaint).scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(Theme.bg)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: text) { value in
                if justPicked { justPicked = false; return }
                scheduleSearch(value)
            }

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions, id: \.self) { s in
                        Button {
                            pick(s)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.accent)
                                Text(s)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if s != suggestions.last { Divider().overlay(Theme.line) }
                    }
                }
                .background(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Lookup

    /// Debounced. Every keystroke is a billable Google call, and firing one per
    /// character bills for six guesses at a street nobody has finished typing.
    private func scheduleSearch(_ q: String) {
        searchTask?.cancel()
        let query = q.trimmingCharacters(in: .whitespaces)
        guard query.count >= 3 else { suggestions = []; return }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await search(query)
        }
    }

    private func search(_ q: String) async {
        searching = true
        defer { searching = false }
        struct Response: Decodable { let suggestions: [String]? }
        do {
            let r = try await API.shared.get("/geo/suggest", query: ["q": q], as: Response.self)
            guard !Task.isCancelled else { return }
            suggestions = r.suggestions ?? []
        } catch {
            // Silent. Losing suggestions leaves a plain text field, which still
            // works; an error box under every third keystroke does not.
            suggestions = []
        }
    }

    private func pick(_ s: String) {
        justPicked = true
        text = s
        suggestions = []
        resolving = true
        errorMessage = nil

        Task {
            struct Geo: Decodable {
                let lat: Double?
                let lng: Double?
                let address: String?
                let city: String?
                let state: String?
                let zip: String?
            }
            defer { resolving = false }
            do {
                let g = try await API.shared.get("/geo/geocode", query: ["q": s], as: Geo.self)
                guard let lat = g.lat, let lng = g.lng else {
                    errorMessage = "Could not find that address on the map."
                    return
                }
                onResolved(Resolved(address: g.address ?? s, lat: lat, lng: lng,
                                    city: g.city, state: g.state, zip: g.zip))
            } catch let e as APIError {
                errorMessage = e.message
            } catch {
                errorMessage = "Could not look that address up."
            }
        }
    }
}
