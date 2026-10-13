#!/usr/bin/env swift
// Runs production SwiftUI Cancel actions without camera or screen capture hardware.
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let source = try String(contentsOf: root.appendingPathComponent("QuickRecorder/ViewModel/CameraOverlayer.swift"), encoding: .utf8)
func extractView(_ marker: String) -> String {
    guard let start = source.range(of: marker),
          let end = source[start.lowerBound...].range(of: "\n}") else {
        fatalError("View not found: \(marker)")
    }
    // Deliver a test event to the mounted view so its real @State storage is used.
    return String(source[start.lowerBound..<end.upperBound])
        .replacingOccurrences(of: marker, with: marker + "\n    private let cancelTestID = TestEvents.currentID")
        .replacingOccurrences(of: ".background(WindowAccessor",
            with: ".onReceive(NotificationCenter.default.publisher(for: Notification.Name(\"test.cancel\"))) { event in if event.object as? UUID == cancelTestID { cancelSetupView() } }\n        .background(WindowAccessor")
}
let windowAccessor = try String(contentsOf: root.appendingPathComponent("QuickRecorder/Supports/WindowAccessor.swift"), encoding: .utf8)
let fixtures = #"""
import AppKit
import AVFoundation
import Combine
import CoreGraphics
import SwiftUI

extension String { var local: String { self } }
enum TestEvents { static var currentID = UUID() }
struct TestDevice { let uniqueID = "test"; let localizedName = "Test device" }
struct SCDisplay { let displayID: CGDirectDisplayID = 1 }
struct SCShareableContent {
    let displays = [SCDisplay()]
    static func getExcludingDesktopWindows(_ exclude: Bool, onScreenWindowsOnly: Bool,
        completionHandler: @escaping (SCShareableContent?, Error?) -> Void) {
        completionHandler(SCShareableContent(), nil)
    }
}
extension NSScreen {
    var displayID: CGDirectDisplayID { 1 }
}
enum SCContext {
    static func getCameras() -> [TestDevice] { [TestDevice()] }
    static func getMicrophone() -> [TestDevice] { [TestDevice()] }
}
struct WebcamScreenLayout {
    enum Position: String, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    var position: Position = .bottomRight
    var widthFraction = 0.28
    var mirrored = true
}
class TestRecorder: ObservableObject {
    enum State { case idle, preparing, previewing, countdown, starting, recording, paused, finishing }
    @Published var state: State = .idle
    @Published var previewImage: NSImage?
    @Published var previewSession: AVCaptureSession?
    @Published var actualFormatDescription = ""
    @Published var errorMessage: String?
    @Published var countdownRemaining = 0
    @Published var recordedDuration: TimeInterval = 0
    var isPaused: Bool { state == .paused }
    var cleanupPending = false
    var cancelCalls = 0
    func updateLayout(_ layout: WebcamScreenLayout) {}
    func startPreview(cameraID: String, microphoneID: String = "", displayID: CGDirectDisplayID = 1, captureSystemAudio: Bool = false) { state = .previewing }
    func startRecording(autoStopMinutes: Int, remuxAudio: Bool = false) { state = .recording }
    func pauseRecording() {}
    func stopRecording() {}
    func cancelPreview() {
        guard state == .preparing || state == .previewing || state == .countdown else { return }
        cancelCalls += 1
        cleanupPending = true
        state = .finishing
    }
    func finishCleanup() {
        cleanupPending = false
        previewImage = nil
        previewSession = nil
        state = .idle
    }
}
final class WebcamRecorder: TestRecorder { static let shared = WebcamRecorder() }
final class WebcamScreenRecorder: TestRecorder { static let shared = WebcamScreenRecorder() }
struct WebcamPreviewView: View {
    let session: AVCaptureSession
    let mirrored: Bool
    var body: some View { Color.black }
}
final class AppDelegate {
    static let shared = AppDelegate()
    var reopenCalls = 0
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        precondition(!WebcamRecorder.shared.cleanupPending && !WebcamScreenRecorder.shared.cleanupPending,
            "Main UI must not reopen while capture cleanup is pending")
        reopenCalls += 1
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "QuickRecorder"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return false
    }
}
"""#
let tests = #"""
func pump(_ seconds: TimeInterval = 0.15) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
    print("PASS: \(message)")
}
func runCancelTest<V: View>(_ title: String, recorder: TestRecorder, state: TestRecorder.State, view: () -> V) {
    NSApp.windows.filter { $0.title == "QuickRecorder" }.forEach { $0.close() }
    recorder.state = state
    recorder.cancelCalls = 0
    let reopenBefore = AppDelegate.shared.reopenCalls
    TestEvents.currentID = UUID()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 555),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: view())
    window.makeKeyAndOrderFront(nil)
    pump()
    // Mode 1 automatically prepares on appearance; allow an idle-case test too.
    recorder.state = state
    pump()
    NotificationCenter.default.post(name: Notification.Name("test.cancel"), object: TestEvents.currentID)
    var heartbeat = false
    DispatchQueue.main.async { heartbeat = true }
    pump()
    check(heartbeat, "\(title) Cancel leaves the main run loop responsive")
    if state != .idle {
        check(window.isVisible && recorder.cleanupPending,
            "\(title) keeps its UI alive until asynchronous preview cleanup completes")
        check(AppDelegate.shared.reopenCalls == reopenBefore, "\(title) does not reopen main UI before cleanup")
        // Duplicate clicks / close callbacks must not start another cleanup.
        NotificationCenter.default.post(name: Notification.Name("test.cancel"), object: TestEvents.currentID)
        pump()
        check(recorder.cancelCalls == 1, "\(title) cancellation is idempotent")
        recorder.finishCleanup()
        pump()
    }
    check(!window.isVisible, "\(title) closes its setup window after cancellation")
    check(AppDelegate.shared.reopenCalls == reopenBefore + 1 && NSApp.windows.contains { $0.title == "QuickRecorder" && $0.isVisible },
        "\(title) returns to the main UI exactly once")
    // NSWindow is retained after close; stale views must not react to later sessions.
    recorder.state = .previewing
    pump()
    recorder.state = .idle
    pump()
    check(AppDelegate.shared.reopenCalls == reopenBefore + 1,
        "\(title) does not reopen main UI again when a later session becomes idle")
    window.contentView = nil
    pump()
}
setbuf(stdout, nil)
NSApplication.shared.setActivationPolicy(.prohibited)
for state in [TestRecorder.State.previewing, .preparing, .idle] {
    runCancelTest("Webcam", recorder: WebcamRecorder.shared, state: state) { WebcamRecordingView() }
    runCancelTest("Webcam + Screen", recorder: WebcamScreenRecorder.shared, state: state) { WebcamScreenRecordingView() }
}
print("All hardware-independent Webcam Cancel UI tests passed.")
"""#
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuickRecorder-CancelUI-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let runner = directory.appendingPathComponent("CancelUI.swift")
let executable = directory.appendingPathComponent("CancelUI")
try (fixtures + "\n" + windowAccessor + "\n" + extractView("struct WebcamRecordingView: View {") + "\n" + extractView("@available(macOS 13, *)\nstruct WebcamScreenRecordingView: View {") + "\n" + tests).write(to: runner, atomically: true, encoding: .utf8)
let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
compiler.arguments = ["swiftc", "-swift-version", "5", runner.path, "-o", executable.path]
try compiler.run()
compiler.waitUntilExit()
guard compiler.terminationStatus == 0 else { exit(1) }
let process = Process()
process.executableURL = executable
try process.run()
// Bound hangs in the UI path instead of requiring Force Quit during verification.
DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
    if process.isRunning { print("FAIL: Cancel UI test timed out"); process.terminate() }
}
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
