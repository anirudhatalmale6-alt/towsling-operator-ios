import SwiftUI
import UIKit          // openSettingsURLString

/// Which jobs are worth waking this company up for.
///
/// Every control on this screen narrows what arrives, so each one says what it
/// costs. "Minimum payout" sounds like a preference until a $90 job three
/// streets away is silently withheld, and the operator concludes the platform
/// is dead rather than that he typed 100 into a box six weeks ago.
struct AlertsView: View {
    @StateObject private var store = AlertsStore()
    @ObservedObject private var push = PushRegistrar.shared
    @ObservedObject private var location = LocationReporter.shared

    /// Local copies. The server is the truth, but a text field bound straight
    /// to the store would fire a save on every keystroke.
    @State private var radiusText = ""
    @State private var minPayoutText = ""
    @State private var quietOn = false
    @State private var quietStart = "22:00"
    @State private var quietEnd = "06:00"

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if store.isLoading && store.prefs == nil {
                        ProgressView().tint(Theme.inkFaint).padding(.vertical, 50)
                    } else if let prefs = store.prefs {
                        permissionCard
                        masterSwitch(prefs)
                        if prefs.enabled {
                            locationCard(prefs)
                            radiusCard(prefs)
                            payoutCard
                            quietCard(prefs)
                        }
                        devicesCard
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
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load()
            fillFields()
        }
    }

    // MARK: - Cards

    /// iOS permission sits above everything else here, because no setting below
    /// can do anything if the phone itself is refusing to show notifications.
    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: push.authorized ? "bell.badge.fill" : "bell.slash.fill")
                .font(.system(size: 15))
                .foregroundStyle(push.authorized ? Theme.green : Theme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text(push.authorized ? "This phone can receive alerts"
                                     : "This phone is blocking alerts")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(push.authorized
                     ? "Everything below decides which jobs are worth one."
                     : "Nothing below can work until notifications are allowed for "
                     + "TowSling in the iPhone Settings app. Until then you will only "
                     + "see jobs while the app is open.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if !push.authorized {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func masterSwitch(_ prefs: AlertPrefs) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { prefs.enabled },
                set: { on in
                    Task { await store.save(["enabled": on],
                                            note: on ? "Job alerts are on." : "Job alerts are off.") }
                }
            )) {
                Text("Send me job alerts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)

            if !prefs.enabled {
                Text("You will not be told about any job. Jobs still appear on the board "
                   + "if you open the app and look.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !prefs.baseSet {
                // The quiet failure this screen exists to prevent. Without a
                // yard the server falls back to the state centroid and the
                // radius below is measured from the wrong place entirely.
                Text("Your yard address is not set, so distances are measured from the "
                   + "middle of your state. Set it on the website under My company, or "
                   + "the mileage below means very little.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// Measured from the truck, or from the yard.
    ///
    /// The switch is per phone, not per company. A driver out on the road wants
    /// jobs near HIM; an owner whose phone lives on the kitchen table forty
    /// miles away does not, and one setting for the whole company cannot serve
    /// both.
    private func locationCard(_ prefs: AlertPrefs) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { location.useDeviceLocation },
                set: { location.setUseDeviceLocation($0) }
            )) {
                Text("Use this phone's location")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)

            Text(location.useDeviceLocation
                 ? "Jobs are measured from where this phone is, so a driver out on the "
                 + "road is offered what is near him rather than what is near the yard."
                 : "Jobs are measured from your yard address, wherever this phone happens to be.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            if location.useDeviceLocation {
                // The promise that makes this safe to leave on. Without it, an
                // app that gets killed or a phone with no signal simply stops
                // being told about work, and that looks exactly like a quiet night.
                Text("If this phone has not reported in a while — app closed, no signal, "
                   + "location turned off — we fall back to your yard. You never stop "
                   + "getting alerts because of this setting.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)

                switch location.authorization {
                case .notDetermined:
                    Button("Allow location") { location.requestPermission() }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                case .denied, .restricted:
                    Text("Location is switched off for TowSling, so we are using your yard. "
                       + "Turn it on in the iPhone Settings app.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                case .authorizedWhenInUse:
                    // Worth saying: While Using looks like it works, right up
                    // until the phone is in a pocket, which is most of the day.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set to \"While Using the App\", so your position only updates "
                           + "while the app is open. Allow \"Always\" and it keeps up while "
                           + "the phone is in your pocket.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Allow always") { location.requestPermission() }
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                default:
                    if let sent = location.lastSentAt {
                        Text("Last updated \(sent.formatted(date: .omitted, time: .shortened)).")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
            } else if !prefs.baseSet {
                Text("You have no yard address either, so you will not be alerted at all "
                   + "until one of the two is set.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func radiusCard(_ prefs: AlertPrefs) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How far out")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Measured from \(location.useDeviceLocation ? "this phone" : "your yard"). "
               + "Leave blank to follow your service radius of \(prefs.serviceRadius) miles — "
               + "one number to keep right instead of two.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("\(prefs.serviceRadius)", text: $radiusText)
                    .keyboardType(.numberPad)
                    .modifier(SettingField())
                Text("miles")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkDim)
                Spacer()
                saveButton {
                    let trimmed = radiusText.trimmingCharacters(in: .whitespaces)
                    await store.save(["radius_miles": trimmed.isEmpty ? NSNull() : Int(trimmed) ?? 0],
                                     note: trimmed.isEmpty
                                        ? "Alerts now follow your service radius."
                                        : "Alerts set to \(trimmed) miles.")
                    fillFields()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var payoutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smallest job worth telling me about")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Your share, after our fee. Set 0 to hear about everything. Anything you "
               + "set here you will never be told about — including a short tow two streets "
               + "away on a quiet night.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("$").font(.system(size: 15)).foregroundStyle(Theme.inkDim)
                TextField("0", text: $minPayoutText)
                    .keyboardType(.decimalPad)
                    .modifier(SettingField())
                Spacer()
                saveButton {
                    let v = Double(minPayoutText.trimmingCharacters(in: .whitespaces)) ?? 0
                    await store.save(["min_payout": v],
                                     note: v == 0 ? "You will hear about every job."
                                                  : "You will only hear about jobs paying you $\(Int(v)) or more.")
                    fillFields()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func quietCard(_ prefs: AlertPrefs) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $quietOn) {
                Text("Quiet hours")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)

            if prefs.is247 {
                Text("Your company is listed as 24/7. Quiet hours will still silence this "
                   + "phone during the window below.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if quietOn {
                HStack(spacing: 10) {
                    TextField("22:00", text: $quietStart)
                        .keyboardType(.numbersAndPunctuation)
                        .modifier(SettingField())
                    Text("to").font(.system(size: 14)).foregroundStyle(Theme.inkDim)
                    TextField("06:00", text: $quietEnd)
                        .keyboardType(.numbersAndPunctuation)
                        .modifier(SettingField())
                }
                Text("24-hour times, in \(prefs.timezone ?? "your local time"). A window that "
                   + "crosses midnight is fine.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkFaint)
            }

            HStack {
                Spacer()
                saveButton {
                    // Sent as a pair, always. The server clears both when either
                    // is empty, which is the only sane reading of half a window.
                    await store.save(quietOn
                        ? ["quiet_start": quietStart, "quiet_end": quietEnd]
                        : ["quiet_start": "", "quiet_end": ""],
                        note: quietOn ? "Quiet from \(quietStart) to \(quietEnd)."
                                      : "Quiet hours off — you will be alerted at any hour.")
                    fillFields()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where alerts go")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)

            if store.devices.isEmpty {
                Text("No devices registered yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
            } else {
                ForEach(store.devices) { device in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: device.isThisApp ? "iphone" : "globe")
                            .font(.system(size: 13))
                            .foregroundStyle(device.health == "ok" ? Theme.green : Theme.inkFaint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.label ?? device.platform ?? "Device")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(device.isThisApp ? "This app · \(device.healthLabel)"
                                                  : "Web browser · \(device.healthLabel)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(device.health == "ok" ? Theme.inkFaint : Theme.amber)
                            if let err = device.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Button {
                Task { await store.sendTest() }
            } label: {
                Label("Send a test alert to my phone", systemImage: "bell.badge")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(GhostButtonStyle())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Bits

    private func saveButton(_ work: @escaping () async -> Void) -> some View {
        Button {
            Task { await work() }
        } label: {
            if store.isSaving {
                ProgressView().tint(Theme.accent).scaleEffect(0.8)
            } else {
                Text("Save").font(.system(size: 14, weight: .bold))
            }
        }
        .foregroundStyle(Theme.accent)
        .disabled(store.isSaving)
    }

    /// Pull the server's values into the local editing copies. Called after
    /// every save as well as on load, so a value the server clamped or refused
    /// is shown as what it actually stored rather than what was typed.
    private func fillFields() {
        guard let p = store.prefs else { return }
        radiusText    = p.radiusMiles.map(String.init) ?? ""
        minPayoutText = p.minPayout > 0 ? String(format: "%.0f", p.minPayout) : ""
        quietOn       = (p.quietStart != nil && p.quietEnd != nil)
        if let s = p.quietStart { quietStart = s }
        if let e = p.quietEnd   { quietEnd = e }
    }
}

/// The boxed input used across the settings screens.
struct SettingField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 11)
            .frame(width: 90, height: 40)
            .background(Theme.bg)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
