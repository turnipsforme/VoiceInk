import Combine
import Foundation
import SwiftUI

#if LOCAL_BUILD
import AppKit

/// Local source builds never initialize Sparkle or install upstream's paid binaries.
@MainActor
final class UpdaterViewModel: NSObject, ObservableObject {
    struct AvailableUpdate: Equatable {
        let versionIdentifier: String
        let displayVersion: String
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    @Published var canCheckForUpdates = true
    @Published private(set) var checksForUpdatesWhenDashboardAppears: Bool
    @Published private(set) var availableUpdate: AvailableUpdate?
    private let defaults = UserDefaults.standard
    private let preferenceKey = "VoiceInkChecksForUpdatesOnLaunch"
    private let lastCheckKey = "VoiceInkLocalLastUpdateCheck"
    private var checking = false

    override init() {
        let defaults = UserDefaults.standard
        checksForUpdatesWhenDashboardAppears =
            (defaults.object(forKey: "VoiceInkChecksForUpdatesOnLaunch") as? Bool)
            ?? (defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool)
            ?? true
        super.init()
    }

    func setChecksForUpdatesWhenDashboardAppears(_ value: Bool) {
        checksForUpdatesWhenDashboardAppears = value
        defaults.set(value, forKey: preferenceKey)
        if value {
            checkForUpdatesIfDue()
        } else {
            availableUpdate = nil
        }
    }

    func checkForUpdatesIfDue() {
        guard checksForUpdatesWhenDashboardAppears, !checking else { return }
        if let last = defaults.object(forKey: lastCheckKey) as? Date,
            Date().timeIntervalSince(last) >= 0,
            Date().timeIntervalSince(last) < 14_400 { return }
        performCheck(userInitiated: false)
    }

    func checkForUpdates() {
        guard !checking else { return }
        performCheck(userInitiated: true)
    }

    private func performCheck(userInitiated: Bool) {
        checking = true
        canCheckForUpdates = false
        Task { @MainActor in
            defer {
                checking = false
                canCheckForUpdates = true
            }
            do {
                var request = URLRequest(url: URL(string:
                    "https://api.github.com/repos/Beingpax/VoiceInk/releases/latest")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("VoiceInk-Local-Source-Build", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                guard !release.draft, !release.prerelease else {
                    throw URLError(.cannotParseResponse)
                }
                defaults.set(Date(), forKey: lastCheckKey)
                let tag = Bundle.main.object(forInfoDictionaryKey: "VoiceInkUpstreamTag") as? String ?? "v0"
                let current = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                if latest.compare(current, options: .numeric) == .orderedDescending {
                    availableUpdate = AvailableUpdate(
                        versionIdentifier: release.tag_name, displayVersion: latest)
                } else {
                    availableUpdate = nil
                }
                if userInitiated { presentResult() }
            } catch {
                if userInitiated {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't check for updates"
                    alert.informativeText = "\(error.localizedDescription)\nNo changes were made. The local unlocked build remains installed."
                    alert.runModal()
                }
            }
        }
    }

    private func presentResult() {
        let alert = NSAlert()
        if let update = availableUpdate {
            alert.messageText = "VoiceInk \(update.displayVersion) is available"
            alert.informativeText = "Rebuild from the new stable source release with all Pro features enabled. The updater opens in Terminal, builds on this fork's macOS runner, and replaces VoiceInk only after verification and a backup. Settings, modes, history, and models are retained. Finish any recording before updating. Official paid app downloads are never installed."
            alert.addButton(withTitle: "Rebuild & Install")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            guard let helper = Bundle.main.url(forResource: "VoiceInkLocalUpdate", withExtension: "command") else {
                let error = NSAlert()
                error.messageText = "Local updater is missing"
                error.informativeText = "Run ~/Developer/VoiceInk-local/local/update-voiceink.sh in Terminal. No official update will be installed."
                error.runModal()
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Terminal", helper.path]
            try? process.run()
        } else {
            alert.messageText = "VoiceInk is up to date"
            alert.informativeText = "All Pro features are enabled in this local source build. Future updates use the same unlocked build process, not the official paid app."
            alert.runModal()
        }
    }
}
#else
import Sparkle

@MainActor
final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    struct AvailableUpdate: Equatable {
        let versionIdentifier: String
        let displayVersion: String
    }

    private enum DefaultsKey {
        // Keep the existing persisted key strings so current user preferences migrate automatically.
        static let automaticUpdateChecks = "VoiceInkChecksForUpdatesOnLaunch"
        static let interactedUpdateVersions = "VoiceInkInteractedUpdateVersions"
        static let sparkleAutomaticChecks = "SUEnableAutomaticChecks"
    }

    private let defaults: UserDefaults
    private var isUserInitiatedUpdateCheck = false
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    @Published var canCheckForUpdates = false
    @Published private(set) var checksForUpdatesWhenDashboardAppears = false
    @Published private(set) var availableUpdate: AvailableUpdate?

    override init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        checksForUpdatesWhenDashboardAppears = Self.initialAutomaticCheckPreference(in: defaults)
        super.init()

        let updater = updaterController.updater

        // VoiceInk owns automatic discovery through Sparkle's non-presenting probe.
        // Keeping Sparkle's scheduler disabled prevents it from showing an update
        // window independently of the Dashboard button.
        updater.automaticallyChecksForUpdates = false
        updaterController.startUpdater()

        canCheckForUpdates = updater.canCheckForUpdates
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func setChecksForUpdatesWhenDashboardAppears(_ value: Bool) {
        guard checksForUpdatesWhenDashboardAppears != value else { return }

        checksForUpdatesWhenDashboardAppears = value
        defaults.set(value, forKey: DefaultsKey.automaticUpdateChecks)

        if value {
            checkForUpdateInformationIfPossible()
        } else {
            availableUpdate = nil
        }
    }

    func checkForUpdatesIfDue() {
        guard checksForUpdatesWhenDashboardAppears else { return }

        let updater = updaterController.updater
        guard !updater.sessionInProgress else { return }

        if let lastCheckDate = updater.lastUpdateCheckDate {
            let elapsed = Date().timeIntervalSince(lastCheckDate)
            guard elapsed < 0 || elapsed >= updater.updateCheckInterval else { return }
        }

        checkForUpdateInformationIfPossible()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }

        // Any explicit check is interaction with the currently advertised update.
        // Persist it before presenting Sparkle so dismissing or closing the native
        // window cannot make the Dashboard button reappear for the same build.
        if let availableUpdate {
            rememberInteraction(with: availableUpdate.versionIdentifier)
            self.availableUpdate = nil
        }

        if !updaterController.updater.sessionInProgress {
            isUserInitiatedUpdateCheck = true
        }
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let update = AvailableUpdate(
            versionIdentifier: item.versionString,
            displayVersion: item.displayVersionString
        )

        if isUserInitiatedUpdateCheck {
            rememberInteraction(with: update.versionIdentifier)
            availableUpdate = nil
        } else if checksForUpdatesWhenDashboardAppears && !hasInteracted(with: update.versionIdentifier) {
            availableUpdate = update
        } else {
            availableUpdate = nil
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableUpdate = nil
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        isUserInitiatedUpdateCheck = false
    }

    private func checkForUpdateInformationIfPossible() {
        let updater = updaterController.updater
        guard !updater.sessionInProgress else { return }
        updater.checkForUpdateInformation()
    }

    private func hasInteracted(with versionIdentifier: String) -> Bool {
        defaults.stringArray(forKey: DefaultsKey.interactedUpdateVersions)?
            .contains(versionIdentifier) == true
    }

    private func rememberInteraction(with versionIdentifier: String) {
        var versions = defaults.stringArray(forKey: DefaultsKey.interactedUpdateVersions) ?? []
        guard !versions.contains(versionIdentifier) else { return }
        versions.append(versionIdentifier)
        defaults.set(versions, forKey: DefaultsKey.interactedUpdateVersions)
    }

    private static func initialAutomaticCheckPreference(in defaults: UserDefaults) -> Bool {
        if let preference = defaults.object(forKey: DefaultsKey.automaticUpdateChecks) as? Bool {
            return preference
        }

        // Preserve an explicit choice made through VoiceInk's previous Sparkle-backed
        // setting. With no saved choice, keep VoiceInk's existing opt-in default.
        let preference = (defaults.object(forKey: DefaultsKey.sparkleAutomaticChecks) as? Bool) ?? true

        defaults.set(preference, forKey: DefaultsKey.automaticUpdateChecks)
        return preference
    }
}

#endif

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}
