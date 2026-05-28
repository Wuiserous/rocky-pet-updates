import AppKit
import Combine
import Foundation

enum AppUpdateError: LocalizedError {
    case invalidVersionMetadataURL
    case invalidVersionMetadata
    case unsupportedInstallLocation
    case couldNotMountDiskImage
    case couldNotFindAppInDiskImage
    case couldNotPrepareInstaller
    case couldNotStartInstaller

    var errorDescription: String? {
        switch self {
        case .invalidVersionMetadataURL:
            return "Rocky couldn't determine where to check for updates."
        case .invalidVersionMetadata:
            return "Rocky couldn't read the update metadata."
        case .unsupportedInstallLocation:
            return "Move Rocky into Applications before using in-app updates."
        case .couldNotMountDiskImage:
            return "Rocky downloaded the update but couldn't open the DMG."
        case .couldNotFindAppInDiskImage:
            return "Rocky couldn't find the updated app inside the DMG."
        case .couldNotPrepareInstaller:
            return "Rocky couldn't prepare the update installer."
        case .couldNotStartInstaller:
            return "Rocky couldn't start the installer helper."
        }
    }
}

private struct MacVersionManifest: Decodable {
    let version: String
    let build: String?
    let downloadURL: URL
    let keyNote: String?
    let whatsNew: [String]?

    enum CodingKeys: String, CodingKey {
        case version
        case build
        case downloadURL = "download_url"
        case keyNote = "key_note"
        case whatsNew = "whats_new"
    }
}

@MainActor
final class AppUpdateService: ObservableObject {
    @Published private(set) var updaterStatusText: String
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var isInstallingUpdate = false

    let currentVersion: String
    let currentBuild: String

    private let session: URLSession
    private let versionMetadataURL: URL
    private let releasesPageURL: URL

    init(
        session: URLSession = .shared,
        versionMetadataURL: URL = URL(string: "https://raw.githubusercontent.com/Wuiserous/rocky-pet-updates/main/macos/version.json")!,
        releasesPageURL: URL = URL(string: "https://github.com/Wuiserous/rocky-pet-updates/releases")!
    ) {
        let bundle = Bundle.main
        self.currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        self.currentBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        self.session = session
        self.versionMetadataURL = versionMetadataURL
        self.releasesPageURL = releasesPageURL
        self.updaterStatusText = "Rocky checks macOS version metadata when you ask."
    }

    var versionDescription: String {
        "v\(currentVersion) (\(currentBuild))"
    }

    var isUpdaterConfigured: Bool {
        true
    }

    func checkForUpdates() {
        guard !isCheckingForUpdates, !isInstallingUpdate else { return }

        Task { @MainActor [weak self] in
            await self?.runUpdateCheck()
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }

    private func runUpdateCheck() async {
        isCheckingForUpdates = true
        updaterStatusText = "Checking for Rocky updates..."

        do {
            let manifest = try await fetchManifest()
            let comparison = compareManifestVersion(manifest)

            guard comparison == .orderedDescending else {
                isCheckingForUpdates = false
                updaterStatusText = "You're already on the latest Rocky version."
                return
            }

            isCheckingForUpdates = false
            isInstallingUpdate = true
            updaterStatusText = "Downloading Rocky v\(manifest.version)..."

            let downloadedDMGURL = try await downloadDiskImage(from: manifest.downloadURL)
            updaterStatusText = "Preparing Rocky update..."
            try installAndRelaunch(from: downloadedDMGURL)
        } catch {
            isCheckingForUpdates = false
            isInstallingUpdate = false
            updaterStatusText = error.localizedDescription
        }
    }

    private func fetchManifest() async throws -> MacVersionManifest {
        let (data, response) = try await session.data(from: versionMetadataURL)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.invalidVersionMetadata
        }

        let decoder = JSONDecoder()
        return try decoder.decode(MacVersionManifest.self, from: data)
    }

    private func compareManifestVersion(_ manifest: MacVersionManifest) -> ComparisonResult {
        let versionComparison = manifest.version.compare(currentVersion, options: .numeric)
        if versionComparison != .orderedSame {
            return versionComparison
        }

        if let manifestBuild = manifest.build?.trimmingCharacters(in: .whitespacesAndNewlines),
           !manifestBuild.isEmpty {
            return manifestBuild.compare(currentBuild, options: .numeric)
        }

        return .orderedSame
    }

    private func downloadDiskImage(from url: URL) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.invalidVersionMetadata
        }

        let filename = url.lastPathComponent.isEmpty ? "Rocky.dmg" : url.lastPathComponent
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("download")
            .deletingPathExtension()
            .appendingPathExtension((filename as NSString).pathExtension.isEmpty ? "dmg" : (filename as NSString).pathExtension)

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func installAndRelaunch(from diskImageURL: URL) throws {
        let currentAppURL = Bundle.main.bundleURL.standardizedFileURL
        let currentAppPath = currentAppURL.path

        guard currentAppPath.hasSuffix(".app"),
              !currentAppPath.contains("/AppTranslocation/"),
              !currentAppPath.contains("/Volumes/")
        else {
            throw AppUpdateError.unsupportedInstallLocation
        }

        let mountPointURL = try mountDiskImage(at: diskImageURL)
        let updatedAppURL = try findRockyApp(in: mountPointURL)
        let installerScriptURL = try writeInstallerScript(
            currentAppURL: currentAppURL,
            updatedAppURL: updatedAppURL,
            diskImageURL: diskImageURL,
            mountPointURL: mountPointURL
        )

        let installerProcess = Process()
        installerProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        installerProcess.arguments = [installerScriptURL.path]

        do {
            try installerProcess.run()
        } catch {
            throw AppUpdateError.couldNotStartInstaller
        }

        updaterStatusText = "Installing Rocky update and relaunching..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    private func mountDiskImage(at diskImageURL: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-nobrowse", "-plist", diskImageURL.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppUpdateError.couldNotMountDiskImage
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let propertyList = try PropertyListSerialization.propertyList(from: outputData, format: nil)

        guard
            let root = propertyList as? [String: Any],
            let entities = root["system-entities"] as? [[String: Any]],
            let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw AppUpdateError.couldNotMountDiskImage
        }

        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    private func findRockyApp(in mountPointURL: URL) throws -> URL {
        let fileManager = FileManager.default

        if let topLevelApp = try fileManager.contentsOfDirectory(
            at: mountPointURL,
            includingPropertiesForKeys: nil
        ).first(where: { $0.pathExtension == "app" }) {
            return topLevelApp
        }

        if let enumerator = fileManager.enumerator(
            at: mountPointURL,
            includingPropertiesForKeys: nil
        ) {
            for case let candidate as URL in enumerator where candidate.pathExtension == "app" {
                return candidate
            }
        }

        throw AppUpdateError.couldNotFindAppInDiskImage
    }

    private func writeInstallerScript(
        currentAppURL: URL,
        updatedAppURL: URL,
        diskImageURL: URL,
        mountPointURL: URL
    ) throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocky-updater-\(UUID().uuidString).sh")

        let script = """
        #!/bin/bash
        set -euo pipefail

        APP_PATH=\(shellQuoted(currentAppURL.path))
        TEMP_APP_PATH="${APP_PATH}.new"
        NEW_APP_PATH=\(shellQuoted(updatedAppURL.path))
        DMG_PATH=\(shellQuoted(diskImageURL.path))
        MOUNT_PATH=\(shellQuoted(mountPointURL.path))
        PID=\(ProcessInfo.processInfo.processIdentifier)

        while kill -0 "$PID" 2>/dev/null; do
          sleep 1
        done

        if [[ "$APP_PATH" != *.app ]]; then
          exit 1
        fi

        rm -rf "$TEMP_APP_PATH"
        ditto "$NEW_APP_PATH" "$TEMP_APP_PATH"
        rm -rf "$APP_PATH"
        mv "$TEMP_APP_PATH" "$APP_PATH"
        hdiutil detach "$MOUNT_PATH" -quiet || true
        open "$APP_PATH"
        rm -f "$DMG_PATH"
        rm -f "$0"
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            throw AppUpdateError.couldNotPrepareInstaller
        }

        return scriptURL
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
