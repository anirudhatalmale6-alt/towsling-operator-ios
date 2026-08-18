import SwiftUI

/// Editing the company address, and what it can tow.
///
/// These two live on one screen because they are the two things that decide
/// which work reaches this company: the address is where distance is measured
/// from when a phone has not reported, and the checkboxes decide which jobs are
/// eligible at all. Changing either quietly changes how much work arrives, so
/// both say so.
struct CompanyEditor: View {
    let company: Company
    let onSave: ([String: Any], String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var radiusText = ""
    @State private var dot = ""
    @State private var mc = ""
    @State private var is247 = false
    @State private var flags: [String: Bool] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Yard address")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text("Where distance is measured from whenever a driver's phone "
                               + "has not reported recently. Getting this wrong is the "
                               + "commonest reason a company sees the wrong jobs.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)

                            field("Street") {
                                TextField("", text: $address)
                                    .textContentType(.streetAddressLine1)
                            }
                            field("City") {
                                TextField("", text: $city)
                                    .textContentType(.addressCity)
                            }
                            HStack(spacing: 10) {
                                field("State") {
                                    TextField("FL", text: $state)
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled()
                                }
                                field("ZIP") {
                                    TextField("", text: $zip)
                                        .keyboardType(.numbersAndPunctuation)
                                        .textContentType(.postalCode)
                                }
                            }

                            // Said plainly rather than left as a surprise. The
                            // app cannot geocode an address, so typing one here
                            // does not by itself move the point jobs are
                            // measured from.
                            Text("Changing the address here updates your record. The map point "
                               + "it is measured from is set on the website, where the address "
                               + "is looked up properly.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .cardBackground(padding: 16)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("How you operate")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.ink)

                            HStack(spacing: 10) {
                                field("Service radius") {
                                    TextField("25", text: $radiusText)
                                        .keyboardType(.numberPad)
                                }
                                field("DOT") { TextField("", text: $dot) }
                            }
                            field("MC number") { TextField("", text: $mc) }

                            Toggle(isOn: $is247) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Open 24/7")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text("A 24/7 company is never silenced by quiet hours.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.inkFaint)
                                }
                            }
                            .tint(Theme.accent)
                        }
                        .cardBackground(padding: 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("What you can tow")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            // The one warning that matters on this screen. A
                            // company with heavy duty unticked will never be
                            // offered a Semi or an RV, however close the truck
                            // is — which is exactly the bug Ricardo found.
                            Text("Only jobs matching these ever reach you. Unticking something "
                               + "is how a company stops seeing that work entirely.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(company.capabilities, id: \.key) { cap in
                                Toggle(isOn: Binding(
                                    get: { flags[cap.key] ?? cap.on },
                                    set: { flags[cap.key] = $0 }
                                )) {
                                    Text(cap.label)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.ink)
                                }
                                .tint(Theme.accent)
                            }
                        }
                        .cardBackground(padding: 16)
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit company")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        address    = company.address ?? ""
        city       = company.city ?? ""
        state      = company.state ?? ""
        zip        = company.zip ?? ""
        radiusText = company.serviceRadiusMiles.map(String.init) ?? ""
        dot        = company.dotNumber ?? ""
        mc         = company.mcNumber ?? ""
        is247      = company.is247
        flags      = Dictionary(uniqueKeysWithValues: company.capabilities.map { ($0.key, $0.on) })
    }

    private func save() {
        var body: [String: Any] = [
            "address": address.trimmingCharacters(in: .whitespaces),
            "city":    city.trimmingCharacters(in: .whitespaces),
            "state":   state.trimmingCharacters(in: .whitespaces).uppercased(),
            "zip":     zip.trimmingCharacters(in: .whitespaces),
            "dot_number": dot.trimmingCharacters(in: .whitespaces),
            "mc_number":  mc.trimmingCharacters(in: .whitespaces),
            "is_24_7": is247,
        ]
        if let r = Int(radiusText.trimmingCharacters(in: .whitespaces)), r > 0 {
            body["service_radius_miles"] = r
        }
        // Every flag, every time. Sending only the changed ones would work until
        // somebody unticks the last one on a screen that then sends nothing.
        for cap in company.capabilities {
            body[cap.key] = flags[cap.key] ?? cap.on
        }
        onSave(body, "Company saved.")
        dismiss()
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Theme.inkDim)
            content()
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background(Theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
