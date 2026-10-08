#!/usr/bin/env swift
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let projectRoot = scriptURL.deletingLastPathComponent()
let sourceURL = projectRoot.appendingPathComponent("QuickRecorder/ViewModel/CameraOverlayer.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let marker = "@available(macOS 13, *)\nstruct WebcamScreenRecordingView: View {"
guard let viewStart = source.range(of: marker),
      let viewEnd = source[viewStart.lowerBound...].range(of: "\n}") else {
    fatalError("Could not extract WebcamScreenRecordingView from \(sourceURL.path)")
}
let productionView = String(source[viewStart.lowerBound..<viewEnd.upperBound])

let localeFiles = [
    "en": nil,
    "zh-Hant": "zh-Hant.lproj/Localizable.strings",
    "it": "it.lproj/Localizable.strings"
]
var localizedTables = [String: [String: String]]()
for (locale, relativePath) in localeFiles {
    guard let relativePath else {
        localizedTables[locale] = [:]
        continue
    }
    let stringsURL = projectRoot.appendingPathComponent("QuickRecorder/\(relativePath)")
    let data = try Data(contentsOf: stringsURL)
    guard let table = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
        fatalError("Could not parse localized strings table at \(stringsURL.path)")
    }
    localizedTables[locale] = table
}

func swiftDictionary(_ dictionary: [String: String]) -> String {
    if dictionary.isEmpty { return "[:]" }
    let values = dictionary.keys.sorted().map { "\($0.debugDescription): \(dictionary[$0]!.debugDescription)" }
    return "[" + values.joined(separator: ",\n") + "]"
}
let localizedTablesSource = "[" + localizedTables.keys.sorted().map {
    "\($0.debugDescription): \(swiftDictionary(localizedTables[$0]!))"
}.joined(separator: ",\n") + "]"

let runnerSource = """
import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

private enum DemoLocalization {
    static let tables: [String: [String: String]] = \(localizedTablesSource)
    static var active: [String: String] = [:]
}

extension String {
    var local: String { DemoLocalization.active[self] ?? self }
}

private struct DemoCamera {
    let uniqueID: String
    let localizedName: String
}

private struct DemoMicrophone {
    let uniqueID: String
    let localizedName: String
}

private struct SCDisplay {
    let displayID: CGDirectDisplayID
}

private struct SCShareableContent {
    let displays: [SCDisplay]

    static func getExcludingDesktopWindows(
        _ excludeDesktopWindows: Bool,
        onScreenWindowsOnly: Bool,
        completionHandler: @escaping (SCShareableContent?, Error?) -> Void
    ) {
        if DemoFixtures.missingSources {
            completionHandler(nil, DemoSourceError())
        } else {
            completionHandler(SCShareableContent(displays: DemoFixtures.displays), nil)
        }
    }
}

private enum DemoFixtures {
    static var missingSources = false
    static var displays = [SCDisplay(displayID: 101), SCDisplay(displayID: 202)]
    static var cameras = [DemoCamera(uniqueID: "demo-camera", localizedName: "Studio Webcam")]
    static var microphones = [DemoMicrophone(uniqueID: "demo-microphone", localizedName: "Desk Microphone")]
}

private struct DemoSourceError: LocalizedError {
    var errorDescription: String? { "No displays were found.".local }
}

private enum SCContext {
    static func getCameras() -> [DemoCamera] {
        DemoFixtures.missingSources ? [] : DemoFixtures.cameras
    }

    static func getMicrophone() -> [DemoMicrophone] {
        DemoFixtures.missingSources ? [] : DemoFixtures.microphones
    }
}

private struct WebcamScreenLayout: Equatable {
    enum Position: String, CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    var position: Position = .bottomRight
    var widthFraction: Double = 0.28
    var mirrored = true
}

private final class WebcamScreenRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case previewing
        case countdown
        case starting
        case recording
        case paused
        case finishing
    }

    static let shared = WebcamScreenRecorder()

    @Published var state: State = .idle
    @Published var previewImage: NSImage?
    @Published var actualFormatDescription = ""
    @Published var errorMessage: String?
    @Published var countdownRemaining = 3
    @Published var recordedDuration: TimeInterval = 183

    var isPaused: Bool { state == .paused }

    func startPreview(cameraID: String, microphoneID: String, displayID: CGDirectDisplayID, captureSystemAudio: Bool) {
        state = .previewing
        previewImage = DemoPreview.image
    }

    func updateLayout(_ layout: WebcamScreenLayout) {}
    func startRecording(autoStopMinutes: Int, remuxAudio: Bool) { state = .recording }
    func pauseRecording() { state = isPaused ? .recording : .paused }
    func stopRecording() { state = .finishing }
    func cancelPreview() { state = .idle }
}

private enum DemoPreview {
    static let image: NSImage = {
        let size = NSSize(width: 1600, height: 900)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.12, green: 0.23, blue: 0.37, alpha: 1),
            NSColor(calibratedRed: 0.28, green: 0.43, blue: 0.48, alpha: 1)
        ])?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor.white.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: NSRect(x: 90, y: 130, width: 760, height: 560), xRadius: 24, yRadius: 24).fill()
        NSColor(calibratedRed: 0.82, green: 0.62, blue: 0.48, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1160, y: 555, width: 340, height: 250), xRadius: 28, yRadius: 28).fill()
        NSString(string: "Synthetic full-frame preview").draw(
            at: NSPoint(x: 120, y: 735),
            withAttributes: [.font: NSFont.systemFont(ofSize: 48, weight: .semibold), .foregroundColor: NSColor.white]
        )
        image.unlockFocus()
        return image
    }()
}

private struct WindowAccessor: View {
    let onWindowClose: () -> Void
    var body: some View { Color.clear }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

\(productionView)

private struct RenderSnapshot {
    let name: String
    let state: WebcamScreenRecorder.State
    let usesPreviewImage: Bool
    let missingSources: Bool
    let errorMessage: String?
}

extension WebcamScreenRecordingView {
    fileprivate init(snapshot: RenderSnapshot) {
        _recorder = StateObject(wrappedValue: WebcamScreenRecorder.shared)
        _cameras = State(initialValue: snapshot.missingSources ? [] : DemoFixtures.cameras)
        _microphones = State(initialValue: snapshot.missingSources ? [] : DemoFixtures.microphones)
        _displays = State(initialValue: snapshot.missingSources ? [] : DemoFixtures.displays)
        _selectedCameraID = State(initialValue: snapshot.missingSources ? "" : "demo-camera")
        _selectedMicrophoneID = State(initialValue: snapshot.missingSources ? "" : "demo-microphone")
        _selectedDisplayID = State(initialValue: snapshot.missingSources ? 0 : 101)
        _captureSystemAudio = State(initialValue: !snapshot.missingSources)
        _remuxAudio = State(initialValue: true)
        _layout = State(initialValue: WebcamScreenLayout())
        _autoStopMinutes = State(initialValue: 15)
        _refreshingSources = State(initialValue: false)
        _sourceError = State(initialValue: snapshot.errorMessage)
    }
}

@MainActor
private func render(_ snapshot: RenderSnapshot, locale: String, into outputDirectory: URL) throws {
    DemoLocalization.active = DemoLocalization.tables[locale] ?? [:]
    DemoFixtures.missingSources = snapshot.missingSources
    let recorder = WebcamScreenRecorder.shared
    recorder.state = snapshot.state
    recorder.previewImage = snapshot.usesPreviewImage ? DemoPreview.image : nil
    recorder.actualFormatDescription = snapshot.usesPreviewImage ? "1920 × 1080 · 30 fps" : ""
    recorder.errorMessage = nil
    recorder.countdownRemaining = 3
    recorder.recordedDuration = 183

    let hostingView = NSHostingView(rootView: WebcamScreenRecordingView(snapshot: snapshot)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\\.colorScheme, .light))
    hostingView.appearance = NSAppearance(named: .aqua)
    hostingView.frame = NSRect(x: 0, y: 0, width: 780, height: 555)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 780, height: 555),
        styleMask: [],
        backing: .buffered,
        defer: false
    )
    window.title = "QuickRecorder UI Snapshot"
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    hostingView.layoutSubtreeIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()

    guard hostingView.bounds.width == 780, hostingView.bounds.height == 555 else {
        throw NSError(domain: "WebcamScreenUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hosting view did not retain the 780×555 canvas"])
    }
    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw NSError(domain: "WebcamScreenUI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not allocate snapshot bitmap"])
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]), png.count > 100 else {
        throw NSError(domain: "WebcamScreenUI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Snapshot was empty"])
    }
    let destination = outputDirectory.appendingPathComponent(snapshot.name + ".png")
    try png.write(to: destination, options: .atomic)
    print("Wrote " + destination.path)
    window.contentView = nil
    window.close()
}

@MainActor
private func renderAll(outputRoot: URL) throws {
    let snapshots = [
        RenderSnapshot(name: "idle-placeholder", state: .idle, usesPreviewImage: false, missingSources: false, errorMessage: nil),
        RenderSnapshot(name: "preparing-progress", state: .preparing, usesPreviewImage: false, missingSources: false, errorMessage: nil),
        RenderSnapshot(name: "previewing-composite", state: .previewing, usesPreviewImage: true, missingSources: false, errorMessage: nil),
        RenderSnapshot(name: "countdown-composite", state: .countdown, usesPreviewImage: true, missingSources: false, errorMessage: nil),
        RenderSnapshot(name: "starting-composite", state: .starting, usesPreviewImage: true, missingSources: false, errorMessage: nil),
        RenderSnapshot(name: "recording-composite", state: .recording, usesPreviewImage: true, missingSources: false, errorMessage: nil),
        RenderSnapshot(name: "paused-composite", state: .paused, usesPreviewImage: true, missingSources: false, errorMessage: nil),
        RenderSnapshot(name: "finishing-composite", state: .finishing, usesPreviewImage: true, missingSources: false, errorMessage: nil),
        RenderSnapshot(name: "missing-sources", state: .idle, usesPreviewImage: false, missingSources: true, errorMessage: nil),
        RenderSnapshot(
            name: "long-error",
            state: .previewing,
            usesPreviewImage: true,
            missingSources: false,
            errorMessage: "The selected camera could not be configured for this display. Reconnect the camera, check its permissions in System Settings, then refresh the available sources before trying again. This deliberately long diagnostic checks that the complete error wraps above the fixed recording controls."
        )
    ]
    let locales = ["en", "zh-Hant", "it"]
    var rendered = 0
    for locale in locales {
        let localeDirectory = outputRoot.appendingPathComponent(locale, isDirectory: true)
        try FileManager.default.createDirectory(at: localeDirectory, withIntermediateDirectories: true)
        for snapshot in snapshots {
            try render(snapshot, locale: locale, into: localeDirectory)
            rendered += 1
        }
    }
    guard rendered == snapshots.count * locales.count else {
        throw NSError(domain: "WebcamScreenUI", code: 4, userInfo: [NSLocalizedDescriptionKey: "Incomplete localized snapshots; wrote \\(rendered)"])
    }
    print("Rendered \\(rendered) snapshots at the 780×555 host size.")
}

let outputRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
NSApplication.shared.setActivationPolicy(.prohibited)
try MainActor.assumeIsolated { try renderAll(outputRoot: outputRoot) }
"""

let outputDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("QuickRecorder-WebcamScreenUI-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let runnerURL = outputDirectory.appendingPathComponent("WebcamScreenUIRunner.swift")
try runnerSource.write(to: runnerURL, atomically: true, encoding: .utf8)
let runnerExecutable = outputDirectory.appendingPathComponent("WebcamScreenUIRunner")
let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
compiler.arguments = ["swiftc", runnerURL.path, "-o", runnerExecutable.path]
try compiler.run()
compiler.waitUntilExit()
guard compiler.terminationStatus == 0 else {
    fatalError("Could not compile the Webcam UI snapshot renderer: \(runnerURL.path)")
}

let process = Process()
process.executableURL = runnerExecutable
process.arguments = [outputDirectory.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("Webcam UI snapshot renderer exited with status \(process.terminationStatus). Generated runner: \(runnerURL.path)")
}
print("Snapshot directory: \(outputDirectory.path)")
