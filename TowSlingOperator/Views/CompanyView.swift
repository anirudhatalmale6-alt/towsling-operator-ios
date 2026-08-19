import SwiftUI
import PhotosUI

/// The company record, its trucks, and the duty switch.
///
/// The duty switch is at the top on purpose. It is the only control here an
/// operator touches at speed — going off duty at the end of a shift, back on
/// at the start of one — and burying it under the address would mean he does
/// not use it, and instead ignores alerts he has no intention of taking.
struct CompanyView: View {
    @StateObject private var store = CompanyStore()
    @State private var editing: Truck?
    @State private var addingTruck = false
    @State private var editingCompany = false
    @State private var verifying: VerifyView.Channel?
    @State private var logoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if store.isLoading && store.company == nil {
                        ProgressView().tint(Theme.inkFaint).padding(.vertical, 50)
                    } else if let company = store.company {
                        dutyCard(company)
                        verificationCard
                        brandCard(company)
                        detailsCard(company)
                        capabilitiesCard(company)
                        trucksCard
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
        .navigationTitle("My company")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .sheet(item: $editing) { truck in
            TruckEditor(truck: truck, isNew: false,
                        types: store.truckTypes, equipment: store.equipmentTypes) { updated in
                Task { await store.saveTruck(updated, isNew: false) }
            } onDelete: {
                Task { await store.deleteTruck(truck) }
            }
        }
        .sheet(item: $verifying) { ch in
            VerifyView(channel: ch,
                       destination: ch == .email ? (store.company?.email ?? "")
                                                 : (store.company?.phone ?? "")) {
                Task { await store.load() }
            }
        }
        .sheet(isPresented: $editingCompany) {
            if let company = store.company {
                CompanyEditor(company: company) { body, note in
                    Task { await store.saveProfile(body, note: note) }
                }
            }
        }
        .sheet(isPresented: $addingTruck) {
            TruckEditor(truck: Truck(id: 0, label: "", truckType: "flatbed",
                                     capacityClass: "light", make: nil, model: nil,
                                     year: nil, plate: nil, equipment: [], notes: nil),
                        isNew: true,
                        types: store.truckTypes, equipment: store.equipmentTypes) { created in
                Task { await store.saveTruck(created, isNew: true) }
            } onDelete: { }
        }
    }

    // MARK: - Cards

    private func dutyCard(_ company: Company) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { store.availableLocal },
                                 set: { on in Task { await store.setAvailable(on) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.availableLocal ? "On duty" : "Off duty")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(store.availableLocal ? Theme.green : Theme.amber)
                    Text(store.availableLocal
                         ? "Jobs near you are offered to your company."
                         : "You will not be offered jobs and will not count as coverage.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.green)

            if !store.availableLocal {
                // Said plainly, because "off duty" sounds like being locked out
                // and an operator who wants one specific job should know he can
                // still take it.
                Text("You can still open the board and take a job yourself while off duty.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private var verificationCard: some View {
        if let v = store.verification, !v.ok {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.amber)
                    Text("Not taking jobs yet")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                if let reason = v.reason {
                    Text(reason)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(v.steps ?? []) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(step.done ? Theme.green : Theme.inkFaint)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink)
                            if let detail = step.detail, !step.done {
                                Text(detail)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.inkFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    /// Logo and reviews — the two things a customer sees about this company that
    /// the company does not otherwise get to look at.
    private func brandCard(_ company: Company) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                CompanyLogo(url: company.logoUrl, fallback: company.name, size: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Company logo")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Shown to the customer beside your name and on the map they watch while you drive to them.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $logoItem, matching: .images) {
                    Text(company.logoUrl == nil ? "Upload a logo" : "Change logo")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                if company.logoUrl != nil {
                    Button("Remove") { Task { await store.removeLogo() } }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.inkDim)
                }
                if store.isUploadingLogo {
                    ProgressView().tint(Theme.inkFaint).scaleEffect(0.7)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Theme.line)

            NavigationLink {
                ReviewsView()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Customer reviews")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        if let n = company.ratingCount, n > 0 {
                            HStack(spacing: 6) {
                                Stars(value: company.ratingAvg ?? 0, size: 12)
                                Text("\(String(format: "%.1f", company.ratingAvg ?? 0)) · \(n) review\(n == 1 ? "" : "s")")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.inkDim)
                            }
                        } else {
                            Text("No reviews yet")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .onChange(of: logoItem) { item in
            guard let item else { return }
            Task {
                // loadTransferable hands back the ORIGINAL bytes, whatever the
                // library holds — and on an iPhone that is HEIC by default. The
                // server only accepts JPEG/PNG/WEBP, and the GD build behind it
                // has no HEIF support at all, so those bytes would be refused
                // with a message about file types for a photo the operator
                // picked out of his own library.
                //
                // Decoding and re-encoding as PNG here makes the format a
                // non-issue: whatever he picks, the server receives a PNG.
                if let data = try? await item.loadTransferable(type: Data.self),
                   let png = UIImage(data: data)?.pngData() {
                    await store.uploadLogo(png)
                } else {
                    store.errorMessage = "That image could not be read. Try another one."
                }
                logoItem = nil
            }
        }
    }

    private func detailsCard(_ company: Company) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(company.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)

            row("Legal name", company.legalName)
            // Tappable while unconfirmed. These two are not paperwork: the
            // board refuses a job until both are done, so a row that only
            // reports the problem and offers no way to fix it is a dead end.
            verifiableRow("Email", company.email, done: company.emailVerified == true, channel: .email)
            verifiableRow("Phone", company.phone, done: company.phoneVerified == true, channel: .phone)
            row("Address", [company.address, company.city, company.state, company.zip]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
            row("DOT", company.dotNumber)
            row("MC", company.mcNumber)
            row("Service radius", company.serviceRadiusMiles.map { "\($0) miles" })
            row("Trucks", company.trucksCount.map(String.init))

            if !company.baseSet {
                Text("Your yard location is not set, so job distances are measured from the "
                   + "middle of your state.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Button("Edit company details") { editingCompany = true }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func capabilitiesCard(_ company: Company) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What you can tow")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
            // This is the list that decides which jobs reach this company at
            // all — a semi will never be offered to a company without heavy
            // duty ticked, however close the truck is.
            Text("Only jobs matching these reach you.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkFaint)

            let on = company.capabilities.filter { $0.on }
            let off = company.capabilities.filter { !$0.on }

            FlowChips(items: on.map(\.label), tint: Theme.green)
            if !off.isEmpty {
                Text("Not offered")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 4)
                FlowChips(items: off.map(\.label), tint: Theme.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var trucksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trucks")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Add") { addingTruck = true }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            if store.trucks.isEmpty {
                Text("No trucks listed yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
            } else {
                ForEach(store.trucks) { truck in
                    Button {
                        editing = truck
                    } label: {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "truck.box.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(truck.label)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text([truck.describedType, truck.capacityClass.capitalized,
                                      [truck.make, truck.model].compactMap { $0 }.joined(separator: " "),
                                      truck.plate]
                                        .compactMap { $0 }.filter { !$0.isEmpty }
                                        .joined(separator: " · "))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.inkFaint)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// A detail row that offers to fix itself.
    @ViewBuilder
    private func verifiableRow(_ label: String, _ value: String?,
                               done: Bool, channel: VerifyView.Channel) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 108, alignment: .leading)
                Text(value)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if done {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.green)
                }
                Spacer(minLength: 0)
                if !done {
                    Button("Confirm") { verifying = channel }
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?, verified: Bool? = nil) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 108, alignment: .leading)
                Text(value)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if verified == true {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.green)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Chips that wrap. Written by hand because SwiftUI on iOS 16 has no flow
/// layout, and a horizontal ScrollView would hide half the list off screen —
/// on a card whose whole job is showing what is missing.
struct FlowChips: View {
    let items: [String]
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows(), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(tint.opacity(0.13))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    /// Three per row. Approximate on purpose — measuring text to pack them
    /// perfectly costs a GeometryReader per chip and buys nothing here.
    private func rows() -> [[String]] {
        stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0 ..< min($0 + 3, items.count)])
        }
    }
}
