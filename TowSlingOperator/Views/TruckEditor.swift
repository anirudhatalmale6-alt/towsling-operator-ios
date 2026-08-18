import SwiftUI

/// Adding or editing one truck.
///
/// The capacity class is the field that matters and the one an operator is
/// least likely to think about: it is what decides whether a Semi/RV job ever
/// reaches this company. So it is second on the form, not buried under the
/// number plate.
struct TruckEditor: View {
    @State var truck: Truck
    let isNew: Bool
    let types: [String]
    let equipment: [String]
    let onSave: (Truck) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var yearText = ""

    private let classes = ["light", "medium", "heavy"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        field("Name it something you would say on the radio") {
                            TextField("Truck 1", text: $truck.label)
                        }

                        picker("Type", selection: $truck.truckType,
                               options: types.isEmpty ? ["flatbed"] : types)

                        VStack(alignment: .leading, spacing: 5) {
                            picker("Carries", selection: $truck.capacityClass, options: classes)
                            Text("This decides which jobs reach you. A heavy recovery is "
                               + "never offered to a company with no heavy truck.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 10) {
                            field("Make") {
                                TextField("", text: Binding(get: { truck.make ?? "" },
                                                            set: { truck.make = $0 }))
                            }
                            field("Model") {
                                TextField("", text: Binding(get: { truck.model ?? "" },
                                                            set: { truck.model = $0 }))
                            }
                        }

                        HStack(spacing: 10) {
                            field("Year") {
                                TextField("", text: $yearText).keyboardType(.numberPad)
                            }
                            field("Plate") {
                                TextField("", text: Binding(get: { truck.plate ?? "" },
                                                            set: { truck.plate = $0 }))
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                            }
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("What is on it")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(Theme.inkDim)
                            ForEach(equipment, id: \.self) { item in
                                Toggle(isOn: Binding(
                                    get: { truck.equipment.contains(item) },
                                    set: { on in
                                        if on {
                                            if !truck.equipment.contains(item) {
                                                truck.equipment.append(item)
                                            }
                                        } else {
                                            truck.equipment.removeAll { $0 == item }
                                        }
                                    }
                                )) {
                                    Text(item.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.ink)
                                }
                                .tint(Theme.accent)
                            }
                        }
                        .cardBackground(padding: 14)

                        field("Notes") {
                            TextField("", text: Binding(get: { truck.notes ?? "" },
                                                        set: { truck.notes = $0 }))
                        }

                        if !isNew {
                            Button("Remove this truck") { confirmingDelete = true }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.red)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                        }
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isNew ? "Add a truck" : truck.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        truck.year = Int(yearText.trimmingCharacters(in: .whitespaces))
                        onSave(truck)
                        dismiss()
                    }
                    .disabled(truck.label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Remove this truck?", isPresented: $confirmingDelete) {
                Button("Remove", role: .destructive) { onDelete(); dismiss() }
                Button("Keep it", role: .cancel) { }
            } message: {
                Text("Jobs it has already done keep their record.")
            }
            .onAppear { yearText = truck.year.map(String.init) ?? "" }
        }
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

    private func picker(_ label: String, selection: Binding<String>,
                        options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Theme.inkDim)
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.replacingOccurrences(of: "_", with: " ").capitalized)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .frame(height: 46)
            .background(Theme.bg)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
