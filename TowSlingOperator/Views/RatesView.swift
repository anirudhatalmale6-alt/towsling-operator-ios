import SwiftUI

/// What this company charges.
///
/// These numbers are not billed from — a customer pays the platform price. They
/// are what the platform matches itself against when it sets that price, which
/// makes a wrong number here expensive in a way that is not obvious from the
/// screen. So blanks stay blank: an unanswered line is left out of the market
/// average entirely, while a 0 would drag it down for every company in the city.
struct RatesView: View {
    @StateObject private var store = RatesStore()
    @State private var dirty = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if store.isLoading && store.rows.isEmpty {
                        ProgressView().tint(Theme.inkFaint).padding(.vertical, 50)
                    } else {
                        header

                        ForEach($store.rows) { $row in
                            rateCard($row)
                        }

                        if let message = store.errorMessage {
                            Text(message)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Theme.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardBackground(padding: 13)
                        }
                        if let note = store.savedNote, !dirty {
                            Text(note)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardBackground(padding: 13)
                        }

                        Button {
                            Task {
                                await store.save()
                                dirty = false
                            }
                        } label: {
                            if store.isSaving { ProgressView().tint(.white) }
                            else { Text("Save my rates") }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: dirty))
                        .disabled(!dirty || store.isSaving)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.load() }
        }
        .navigationTitle("My rates")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.note ?? "Your rates help us set fair prices in your area. "
                             + "They are never shown to another company.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            Text("Leave anything you do not do blank. Blank means \"I have not answered\", "
               + "which is not the same as free — and a 0 here would tell us you tow for nothing.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func rateCard(_ row: Binding<RateRow>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.wrappedValue.label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)

            money("Call price", row.baseFee,
                  hint: row.wrappedValue.asksMiles ? "What the job starts at" : "The whole job")

            if row.wrappedValue.asksHook {
                money("Hook fee", row.hookFee, hint: "Leave blank if the call price covers it")
            }
            if row.wrappedValue.asksMiles {
                money("Miles included", row.includedMiles, prefix: "", hint: "Before per-mile starts")
                money("Per mile after that", row.perMile, hint: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func money(_ label: String, _ value: Binding<Double?>,
                       prefix: String = "$", hint: String?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.inkDim)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            Spacer(minLength: 8)
            if !prefix.isEmpty {
                Text(prefix).font(.system(size: 15)).foregroundStyle(Theme.inkDim)
            }
            TextField("", text: Binding(
                get: {
                    guard let v = value.wrappedValue else { return "" }
                    // Whole numbers without a trailing .0 — a rate sheet full of
                    // "125.0" reads like a spreadsheet, not a price list.
                    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
                },
                set: { text in
                    let cleaned = text.trimmingCharacters(in: .whitespaces)
                    // Empty stays nil. This is the whole point of the screen.
                    value.wrappedValue = cleaned.isEmpty ? nil : Double(cleaned)
                    dirty = true
                }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .modifier(SettingField())
        }
    }
}
