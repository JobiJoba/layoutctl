import AppKit
import CoreGraphics
import Foundation

@main
struct LayoutCTL {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            let command = try Command(arguments: arguments)
            let store = try LayoutStore()
            switch command {
            case let .save(profileName):
                let snapshotter = Snapshotter()
                let windows = try snapshotter.capture()
                let profile = LayoutProfile(
                    profile: profileName,
                    createdAt: Date(),
                    windows: windows
                )
                try store.save(profile)
                print("Saved \(windows.count) windows to profile '\(profileName)'.")
            case let .restore(profileName, options):
                let restorer = LayoutRestorer(store: store)
                let restoredCount = try restorer.restore(profileName: profileName, options: options)
                if options.dryRun {
                    print("Dry run complete for profile '\(profileName)'. \(restoredCount) windows planned.")
                } else {
                    print("Restored \(restoredCount) windows from profile '\(profileName)'.")
                }
            case let .delete(profileName):
                try store.delete(profileName: profileName)
                print("Deleted profile '\(profileName)'.")
            case let .list(options):
                let profiles = try store.listProfiles()
                switch options.format {
                case .plain:
                    for profile in profiles {
                        print(profile.profile)
                    }
                case .json:
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(profiles)
                    if let json = String(data: data, encoding: .utf8) {
                        print(json)
                    }
                }
            case .help:
                Command.printUsage()
            }
        } catch LayoutError.helpRequested {
            Command.printUsage()
        } catch {
            fputs("layoutctl error: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

}

enum Command {
    case save(String)
    case restore(String, RestoreOptions)
    case list(ListOptions)
    case delete(String)
    case help

    init(arguments: [String]) throws {
        guard let first = arguments.first else {
            throw LayoutError.helpRequested
        }

        switch first.lowercased() {
        case "save":
            guard let profile = arguments.dropFirst().first else {
                throw LayoutError.missingProfileName
            }
            self = .save(profile)
        case "restore":
            guard let profile = arguments.dropFirst().first else {
                throw LayoutError.missingProfileName
            }
            var options = RestoreOptions()
            let optionSlice = arguments.dropFirst(2)
            for option in optionSlice {
                switch option {
                case "--dry-run":
                    options.dryRun = true
                default:
                    throw LayoutError.unknownOption(option)
                }
            }
            self = .restore(profile, options)
        case "list":
            var options = ListOptions()
            for option in arguments.dropFirst() {
                switch option {
                case "--json":
                    options.format = .json
                default:
                    throw LayoutError.unknownOption(option)
                }
            }
            self = .list(options)
        case "delete":
            guard let profile = arguments.dropFirst().first else {
                throw LayoutError.missingProfileName
            }
            self = .delete(profile)
        case "help", "--help", "-h":
            self = .help
        default:
            throw LayoutError.unknownCommand(first)
        }
    }

    static func printUsage() {
        let usage = """
        usage:
          layoutctl save <profile>             Snapshot the current desktop layout.
          layoutctl restore <profile> [flags]  Restore a previously saved layout.
                                               --dry-run    Show planned moves without touching windows.
          layoutctl list [--json]              List saved layout profiles.
          layoutctl delete <profile>           Delete a saved layout profile.
          layoutctl help                       Show this help message.
        """
        print(usage)
    }

    struct ListOptions {
        var format: ListFormat = .plain
    }

    enum ListFormat {
        case plain
        case json
    }
}

struct RestoreOptions {
    var dryRun: Bool = false

    static let `default` = RestoreOptions()
}

enum LayoutError: LocalizedError {
    case helpRequested
    case unknownCommand(String)
    case unknownOption(String)
    case missingProfileName
    case unableToCaptureWindows
    case profileNotFound(String)
    case accessibilityPermissionMissing
    case applicationLaunchFailed(bundleIdentifier: String)
    case windowEnumerationFailed(bundleIdentifier: String)
    case failedToMoveWindow(bundleIdentifier: String, windowTitle: String)

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case let .unknownCommand(cmd):
            return "Unknown command '\(cmd)'. Run 'layoutctl help' for usage."
        case let .unknownOption(option):
            return "Unknown option '\(option)'."
        case .missingProfileName:
            return "Profile name is missing."
        case .unableToCaptureWindows:
            return "Failed to capture windows from the current Space."
        case let .profileNotFound(profile):
            return "Layout profile '\(profile)' was not found."
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required. Enable layoutctl under System Settings → Privacy & Security → Accessibility."
        case let .applicationLaunchFailed(bundleIdentifier):
            return "Failed to launch application with bundle identifier '\(bundleIdentifier)'."
        case let .windowEnumerationFailed(bundleIdentifier):
            return "Unable to enumerate windows for application '\(bundleIdentifier)'."
        case let .failedToMoveWindow(bundleIdentifier, windowTitle):
            return "Failed to move window '\(windowTitle)' for application '\(bundleIdentifier)'."
        }
    }
}

struct LayoutProfile: Codable {
    struct Window: Codable {
        struct Rect: Codable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double

            init(rect: CGRect) {
                x = rect.origin.x.double
                y = rect.origin.y.double
                width = rect.size.width.double
                height = rect.size.height.double
            }
        }

        struct Display: Codable {
            let uuid: String
        }

        let bundleIdentifier: String
        let appName: String
        let windowTitle: String
        let frame: Rect
        let display: Display?
        let isFullscreen: Bool

        init(
            bundleIdentifier: String,
            appName: String,
            windowTitle: String,
            frame: Rect,
            display: Display?,
            isFullscreen: Bool
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.appName = appName
            self.windowTitle = windowTitle
            self.frame = frame
            self.display = display
            self.isFullscreen = isFullscreen
        }

        enum CodingKeys: String, CodingKey {
            case bundleIdentifier
            case appName
            case windowTitle
            case frame
            case display
            case isFullscreen
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            appName = try container.decode(String.self, forKey: .appName)
            windowTitle = try container.decode(String.self, forKey: .windowTitle)
            frame = try container.decode(Rect.self, forKey: .frame)
            display = try container.decodeIfPresent(Display.self, forKey: .display)
            isFullscreen = try container.decodeIfPresent(Bool.self, forKey: .isFullscreen) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
            try container.encode(appName, forKey: .appName)
            try container.encode(windowTitle, forKey: .windowTitle)
            try container.encode(frame, forKey: .frame)
            try container.encodeIfPresent(display, forKey: .display)
            if isFullscreen {
                try container.encode(isFullscreen, forKey: .isFullscreen)
            }
        }
    }

    let profile: String
    let createdAt: Date
    let windows: [Window]
}

private extension CGFloat {
    var double: Double { Double(self) }
}

extension LayoutProfile.Window.Rect {
    var cgRect: CGRect {
        CGRect(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

struct Snapshotter {
    func capture() throws -> [LayoutProfile.Window] {
        let windowOptions: CGWindowListOption = [
            .optionOnScreenOnly,
            .excludeDesktopElements
        ]
        guard let infoList = CGWindowListCopyWindowInfo(windowOptions, kCGNullWindowID) as? [[String: Any]] else {
            throw LayoutError.unableToCaptureWindows
        }

        let runningApplications = NSWorkspace.shared.runningApplications
        var fullscreenResolver = FullscreenResolver()
        var snapshots: [LayoutProfile.Window] = []

        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width > 0, rect.height > 0 else {
                continue
            }

            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            guard let app = runningApplications.first(where: { $0.processIdentifier == ownerPID }),
                  let bundleIdentifier = app.bundleIdentifier else {
                continue
            }

            if app.activationPolicy == .prohibited {
                continue
            }

            let windowTitle = (info[kCGWindowName as String] as? String) ?? ""
            let appName = app.localizedName ?? (info[kCGWindowOwnerName as String] as? String) ?? bundleIdentifier
            let displayUUID = displayUUIDForFrame(rect).map { LayoutProfile.Window.Display(uuid: $0) }

            let isFullscreen = fullscreenResolver.isWindowFullscreen(
                app: app,
                title: windowTitle,
                frame: rect
            )

            let window = LayoutProfile.Window(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                windowTitle: windowTitle,
                frame: LayoutProfile.Window.Rect(rect: rect),
                display: displayUUID,
                isFullscreen: isFullscreen
            )

            snapshots.append(window)
        }

        return snapshots
    }

    private func displayUUIDForFrame(_ frame: CGRect) -> String? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        var displayCount: UInt32 = 0
        var error = CGGetActiveDisplayList(0, nil, &displayCount)
        if error != .success {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        error = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        if error != .success {
            return nil
        }

        for display in displays {
            let bounds = CGDisplayBounds(display)
            if bounds.contains(center) {
                guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else {
                    continue
                }
                let uuidString = CFUUIDCreateString(nil, uuidRef) as String
                return uuidString
            }
        }
        return nil
    }

    private struct FullscreenResolver {
        struct WindowState {
            let title: String
            let frame: CGRect?
            let isFullscreen: Bool
        }

        private var cache: [pid_t: [WindowState]] = [:]
        private let fullscreenAttribute: CFString = "AXFullScreen" as CFString

        mutating func isWindowFullscreen(app: NSRunningApplication, title: String, frame: CGRect) -> Bool {
            let states = loadStates(for: app)
            let normalizedTitle = title.normalizedForMatching

            if !normalizedTitle.isEmpty,
               let match = states.first(where: { !$0.title.normalizedForMatching.isEmpty && $0.title.normalizedForMatching == normalizedTitle }) {
                return match.isFullscreen
            }

            let tolerance: CGFloat = 2.0
            if let match = states.first(where: {
                guard let stateFrame = $0.frame else { return false }
                return stateFrame.approximatelyEquals(frame, tolerance: tolerance)
            }) {
                return match.isFullscreen
            }

            if let match = states.first(where: { $0.title.normalizedForMatching.isEmpty }) {
                return match.isFullscreen
            }

            return false
        }

        private mutating func loadStates(for app: NSRunningApplication) -> [WindowState] {
            if let cached = cache[app.processIdentifier] {
                return cached
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
            guard result == AXError.success, let windowElements = value as? [AXUIElement] else {
                cache[app.processIdentifier] = []
                return []
            }

            var states: [WindowState] = []

            for element in windowElements {
                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
                let title = titleValue as? String ?? ""

                let frame = rect(for: element)

                var fullscreenValue: CFTypeRef?
                let fullscreenResult = AXUIElementCopyAttributeValue(element, fullscreenAttribute, &fullscreenValue)
                let isFullscreen = (fullscreenResult == AXError.success) && ((fullscreenValue as? Bool) == true)

                states.append(WindowState(title: title, frame: frame, isFullscreen: isFullscreen))
            }

            cache[app.processIdentifier] = states
            return states
        }

        private func rect(for element: AXUIElement) -> CGRect? {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?

            let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
            let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

            guard positionResult == AXError.success,
                  sizeResult == AXError.success,
                  let posRaw = positionValue,
                  let sizeRaw = sizeValue,
                  CFGetTypeID(posRaw) == AXValueGetTypeID(),
                  CFGetTypeID(sizeRaw) == AXValueGetTypeID() else {
                return nil
            }

            var origin = CGPoint.zero
            var size = CGSize.zero

            let posAX = posRaw as! AXValue
            if AXValueGetType(posAX) == .cgPoint {
                AXValueGetValue(posAX, .cgPoint, &origin)
            }

            let sizeAX = sizeRaw as! AXValue
            if AXValueGetType(sizeAX) == .cgSize {
                AXValueGetValue(sizeAX, .cgSize, &size)
            }

            guard size.width > 0, size.height > 0 else {
                return nil
            }

            return CGRect(origin: origin, size: size)
        }
    }
}

struct LayoutStore {
    private let layoutsDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        layoutsDirectoryURL = home.appendingPathComponent(".layoutctl/layouts", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try FileManager.default.createDirectory(
            at: layoutsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func save(_ profile: LayoutProfile) throws {
        let fileURL = layoutsDirectoryURL.appendingPathComponent("\(profile.profile).json")
        let data = try encoder.encode(profile)
        try data.write(to: fileURL, options: .atomic)
    }

    func load(profileName: String) throws -> LayoutProfile {
        let fileURL = layoutsDirectoryURL.appendingPathComponent("\(profileName).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LayoutError.profileNotFound(profileName)
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(LayoutProfile.self, from: data)
    }

    func delete(profileName: String) throws {
        let fileURL = layoutsDirectoryURL.appendingPathComponent("\(profileName).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LayoutError.profileNotFound(profileName)
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    struct ProfileInfo: Codable {
        let profile: String
        let createdAt: Date?
        let updatedAt: Date?
    }

    func listProfiles() throws -> [ProfileInfo] {
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: layoutsDirectoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var infos: [ProfileInfo] = []

        for url in contents where url.pathExtension.lowercased() == "json" {
            let name = url.deletingPathExtension().lastPathComponent
            let resourceValues = try? url.resourceValues(forKeys: resourceKeys)
            let updatedAt = resourceValues?.contentModificationDate

            var createdAt: Date?
            if let data = try? Data(contentsOf: url),
               let profile = try? decoder.decode(LayoutProfile.self, from: data) {
                createdAt = profile.createdAt
            }

            infos.append(ProfileInfo(profile: name, createdAt: createdAt, updatedAt: updatedAt))
        }

        return infos.sorted { lhs, rhs in
            lhs.profile.localizedCaseInsensitiveCompare(rhs.profile) == .orderedAscending
        }
    }
}

struct LayoutRestorer {
    private let store: LayoutStore
    private let mover = WindowMover()

    init(store: LayoutStore) {
        self.store = store
    }

    func restore(profileName: String, options: RestoreOptions = .default) throws -> Int {
        let profile = try store.load(profileName: profileName)

        if options.dryRun {
            printPlan(for: profile)
            return profile.windows.count
        }

        guard AXIsProcessTrusted() else {
            throw LayoutError.accessibilityPermissionMissing
        }

        let applications = try ensureApplications(for: profile)
        return try apply(profile: profile, with: applications)
    }

    private func ensureApplications(for profile: LayoutProfile) throws -> [String: NSRunningApplication] {
        var running: [String: NSRunningApplication] = [:]
        let bundleIdentifiers = Set(profile.windows.map { $0.bundleIdentifier })

        for bundleIdentifier in bundleIdentifiers {
            if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated }) {
                existing.unhide()
                print("Using running app \(bundleIdentifier).")
                running[bundleIdentifier] = existing
                continue
            }

            print("Launching \(bundleIdentifier)...")
            try launchApplication(bundleIdentifier: bundleIdentifier)
            guard let app = waitForApplication(bundleIdentifier: bundleIdentifier, timeout: 20) else {
                throw LayoutError.applicationLaunchFailed(bundleIdentifier: bundleIdentifier)
            }
            app.unhide()
            running[bundleIdentifier] = app
        }

        return running
    }

    private func launchApplication(bundleIdentifier: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-gj", "-b", bundleIdentifier]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw LayoutError.applicationLaunchFailed(bundleIdentifier: bundleIdentifier)
        }
    }

    private func waitForApplication(bundleIdentifier: String, timeout: TimeInterval) -> NSRunningApplication? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated }) {
                return app
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
    }

    private func apply(profile: LayoutProfile, with applications: [String: NSRunningApplication]) throws -> Int {
        let windowsByBundle = Dictionary(grouping: profile.windows, by: { $0.bundleIdentifier })
        var restoredCount = 0
        var runningApplications = applications

        for (bundleIdentifier, savedWindows) in windowsByBundle {
            guard var app = runningApplications[bundleIdentifier] else {
                print("⚠️  Application \(bundleIdentifier) is not running; skipping \(savedWindows.count) window(s).")
                continue
            }

            let windows: [AXWindowDescriptor]
            do {
                windows = try waitForWindows(for: app, expectedCount: savedWindows.count, timeout: 10)
            } catch let error as LayoutError {
                switch error {
                case .windowEnumerationFailed:
                    print("⚠️  Unable to enumerate windows for \(bundleIdentifier). Attempting to relaunch.")
                    try launchApplication(bundleIdentifier: bundleIdentifier)
                    guard let relaunched = waitForApplication(bundleIdentifier: bundleIdentifier, timeout: 20) else {
                        throw LayoutError.applicationLaunchFailed(bundleIdentifier: bundleIdentifier)
                    }
                    relaunched.unhide()
                    runningApplications[bundleIdentifier] = relaunched
                    app = relaunched
                    windows = try waitForWindows(for: app, expectedCount: savedWindows.count, timeout: 10)
                default:
                    throw error
                }
            } catch {
                throw error
            }
            var remaining = windows

            for savedWindow in savedWindows {
                let matchIndex = remaining.firstIndex(where: { $0.matches(savedWindow) })
                let descriptor: AXWindowDescriptor?
                if let index = matchIndex {
                    descriptor = remaining.remove(at: index)
                } else if !remaining.isEmpty {
                    descriptor = remaining.removeFirst()
                } else {
                    descriptor = nil
                }

                guard let windowDescriptor = descriptor else {
                    print("⚠️  No active window found for '\(savedWindow.windowTitle)' (\(bundleIdentifier)).")
                    continue
                }

                let targetFrame = frameForRestoredWindow(savedWindow)

                do {
                    let context = WindowMover.Context(
                        bundleIdentifier: bundleIdentifier,
                        windowTitle: savedWindow.windowTitle
                    )
                    try mover.moveWindow(
                        windowDescriptor.element,
                        to: targetFrame,
                        context: context
                    )
                    mover.raiseWindow(windowDescriptor.element, context: context)
                    if savedWindow.isFullscreen {
                        mover.maximizeWindow(windowDescriptor.element, context: context)
                    }
                    restoredCount += 1
                } catch {
                    print("❌ AX error while moving '\(savedWindow.windowTitle)' (\(bundleIdentifier)): \(error)")
                    throw LayoutError.failedToMoveWindow(bundleIdentifier: bundleIdentifier, windowTitle: savedWindow.windowTitle)
                }
            }
        }

        return restoredCount
    }

    private func waitForWindows(for app: NSRunningApplication, expectedCount: Int, timeout: TimeInterval) throws -> [AXWindowDescriptor] {
        let deadline = Date().addingTimeInterval(timeout)
        let minimum = max(1, expectedCount)

        while Date() < deadline {
            let windows = try fetchWindows(for: app)
            if windows.count >= minimum {
                return windows
            }
            Thread.sleep(forTimeInterval: 0.4)
        }

        return try fetchWindows(for: app)
    }

    private func fetchWindows(for app: NSRunningApplication) throws -> [AXWindowDescriptor] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        func array(for attribute: CFString) -> [AXUIElement] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, attribute, &value) == .success,
                  let elements = value as? [AXUIElement] else {
                return []
            }
            return elements
        }

        var windowElements = array(for: kAXWindowsAttribute as CFString)

        let allWindowsAttribute = "AXAllWindows" as CFString
        if windowElements.isEmpty {
            windowElements = array(for: allWindowsAttribute)
        } else {
            // Merge unique elements from kAXAllWindowsAttribute to capture hidden windows.
            let allWindows = array(for: allWindowsAttribute)
            for element in allWindows where !windowElements.contains(where: { CFEqual($0, element) }) {
                windowElements.append(element)
            }
        }

        if windowElements.isEmpty {
            throw LayoutError.windowEnumerationFailed(bundleIdentifier: app.bundleIdentifier ?? "pid-\(app.processIdentifier)")
        }

        var descriptors: [AXWindowDescriptor] = []

        for element in windowElements {
            var subroleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success {
                if let subrole = subroleValue as? String,
                   subrole != (kAXStandardWindowSubrole as String) {
                    continue
                }
            }

            var minimizedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
               let isMinimized = minimizedValue as? Bool, isMinimized {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }

            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? ""

            descriptors.append(AXWindowDescriptor(element: element, title: title))
        }

        return descriptors
    }

    private func frameForRestoredWindow(_ window: LayoutProfile.Window) -> CGRect {
        guard window.isFullscreen else {
            return window.frame.cgRect
        }

        if let display = window.display,
           let bounds = boundsForDisplay(uuidString: display.uuid) {
            return bounds
        }

        if let mainDisplayBounds = boundsForDisplay(uuidString: nil) {
            return mainDisplayBounds
        }

        return window.frame.cgRect
    }

    private func boundsForDisplay(uuidString: String?) -> CGRect? {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        if result != .success || displayCount == 0 {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        result = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        if result != .success {
            return nil
        }

        if let uuidString,
           let targetUUID = CFUUIDCreateFromString(nil, uuidString as CFString) {
            for display in displays {
                if let uuidRef = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
                   CFEqual(uuidRef, targetUUID) {
                    return visibleFrame(for: display)
                }
            }
        } else if let primary = displays.first {
            return visibleFrame(for: primary)
        }

        return nil
    }

    private func visibleFrame(for display: CGDirectDisplayID) -> CGRect {
        if let screen = NSScreen.screens.first(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == display }) {
            var frame = screen.frame
            // Nudge to avoid fighting menu bar / dock constraints.
            frame.origin.y += 1
            frame.size.height -= 2
            return frame
        }
        return CGDisplayBounds(display)
    }

    private func printPlan(for profile: LayoutProfile) {
        print("Dry run for profile '\(profile.profile)':")
        let grouped = Dictionary(grouping: profile.windows, by: { $0.bundleIdentifier })

        for (bundleIdentifier, windows) in grouped.sorted(by: { $0.key < $1.key }) {
            print("- \(bundleIdentifier)  (\(windows.count) window\(windows.count == 1 ? "" : "s"))")
            for window in windows {
                let title = window.windowTitle.isEmpty ? "<untitled>" : window.windowTitle
                let frame = window.frame
                let targetDisplay = window.display?.uuid ?? "current display"
                let geometry = String(
                    format: "x:%.0f y:%.0f w:%.0f h:%.0f",
                    frame.x,
                    frame.y,
                    frame.width,
                    frame.height
                )
                print("    • \(title) → \(geometry) on \(targetDisplay)")
            }
        }
    }
}

private struct AXWindowDescriptor {
    let element: AXUIElement
    let title: String

    func matches(_ window: LayoutProfile.Window) -> Bool {
        let savedTitle = window.windowTitle.normalizedForMatching
        guard !savedTitle.isEmpty else {
            return false
        }
        return title.normalizedForMatching == savedTitle
    }
}

private struct WindowMover {
    struct Context {
        let bundleIdentifier: String
        let windowTitle: String
    }

    private let fullscreenAttribute: CFString = "AXFullScreen" as CFString
    private let zoomButtonAttribute: CFString = kAXZoomButtonAttribute as CFString
    private let zoomedAttribute: CFString = "AXZoomed" as CFString
    private let pressAction: CFString = kAXPressAction as CFString

    enum WindowMoverError: Error {
        case invalidPosition
        case invalidSize
        case setPositionFailed(AXError)
        case setSizeFailed(AXError)
    }

    func moveWindow(_ window: AXUIElement, to frame: CGRect, context: Context) throws {
        try exitFullscreenIfNeeded(window, context: context)

        var origin = frame.origin
        guard let positionValue = AXValueCreate(.cgPoint, &origin) else {
            throw WindowMoverError.invalidPosition
        }

        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowMoverError.invalidSize
        }

        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        if let error = Self.evaluate(result: positionResult, intent: "position", frame: frame, context: context) {
            throw error
        }

        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        if let error = Self.evaluate(result: sizeResult, intent: "size", frame: frame, context: context) {
            throw error
        }
    }

    func raiseWindow(_ window: AXUIElement, context: Context) {
        let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if result != .success {
            let title = context.windowTitle.isEmpty ? "<untitled>" : context.windowTitle
            print("⚠️  Unable to raise window '\(title)' (\(context.bundleIdentifier)): \(result).")
        }
    }

    func maximizeWindow(_ window: AXUIElement, context: Context) {
        var zoomedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, zoomedAttribute, &zoomedValue) == .success,
           let isZoomed = zoomedValue as? Bool,
           isZoomed {
            return
        }

        var buttonValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, zoomButtonAttribute, &buttonValue)
        guard result == .success,
              let buttonRaw = buttonValue,
              CFGetTypeID(buttonRaw) == AXUIElementGetTypeID() else {
            let title = context.windowTitle.isEmpty ? "<untitled>" : context.windowTitle
            print("⚠️  Unable to find zoom button for '\(title)' (\(context.bundleIdentifier)).")
            return
        }

        let buttonElement = buttonRaw as! AXUIElement
        let pressResult = AXUIElementPerformAction(buttonElement, pressAction)
        if pressResult != .success {
            let title = context.windowTitle.isEmpty ? "<untitled>" : context.windowTitle
            print("⚠️  Unable to maximize '\(title)' (\(context.bundleIdentifier)): \(pressResult).")
        } else {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private static func evaluate(result: AXError, intent: String, frame: CGRect, context: Context) -> Error? {
        guard result != .success else { return nil }

        switch result {
        case .attributeUnsupported, .cannotComplete, .notImplemented, .noValue, .actionUnsupported:
            let title = context.windowTitle.isEmpty ? "<untitled>" : context.windowTitle
            let geometry = String(format: "x:%.0f y:%.0f w:%.0f h:%.0f", frame.origin.x, frame.origin.y, frame.width, frame.height)
            print("⚠️  Partial \(intent) update for '\(title)' (\(context.bundleIdentifier)): \(result). Window may already be at \(geometry).")
            return nil
        default:
            return intent == "position"
                ? WindowMoverError.setPositionFailed(result)
                : WindowMoverError.setSizeFailed(result)
        }
    }

    private func exitFullscreenIfNeeded(_ window: AXUIElement, context: Context) throws {
        var fullscreenValue: CFTypeRef?
        let getResult = AXUIElementCopyAttributeValue(window, fullscreenAttribute, &fullscreenValue)
        guard getResult == AXError.success else { return }

        if let isFullscreen = fullscreenValue as? Bool, isFullscreen {
            let setResult = AXUIElementSetAttributeValue(window, fullscreenAttribute, kCFBooleanFalse)
            if setResult != AXError.success {
                let title = context.windowTitle.isEmpty ? "<untitled>" : context.windowTitle
                print("⚠️  Unable to exit fullscreen for '\(title)' (\(context.bundleIdentifier)): \(setResult).")
            } else {
                // Give macOS a moment to transition out of fullscreen before moving.
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }
}

private extension String {
    var normalizedForMatching: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension CGRect {
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance &&
            abs(origin.y - other.origin.y) <= tolerance &&
            abs(size.width - other.size.width) <= tolerance &&
            abs(size.height - other.size.height) <= tolerance
    }
}
