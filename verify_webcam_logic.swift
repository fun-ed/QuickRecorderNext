// Run with: swift verify_webcam_logic.swift
// Exercises the production WebcamRecorder with simulated native output callbacks.
// Does not request camera/microphone permissions or record physical devices.
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let production = try String(contentsOf: root.appendingPathComponent("QuickRecorder/AVContext.swift"), encoding: .utf8)
guard let start = production.range(of: "final class WebcamRecorder:") else {
    fatalError("WebcamRecorder definition was not found")
}
let backend = String(production[start.lowerBound...])
let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("quickrecorder-webcam-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

let fixtures = #"""
import Foundation
import AppKit
import AVFoundation
import Combine
import SwiftUI
import VideoToolbox

enum Encoder: String { case h264, h265 }
enum StreamType { case camera, screen }
final class WebcamScreenRecorder {
    static let shared = WebcamScreenRecorder()
    var isBusy = false
}
final class SCContext {
    static var streamType: StreamType?
    static var filePath = ""
    static var autoStop = 0
    static var isPaused = false
    static var timePassed: TimeInterval = 0
    static var startTime: Date?
    static var notifications = [(String, String)]()
    static func getCameras() -> [AVCaptureDevice] { [] }
    static func getMicrophone() -> [AVCaptureDevice] { [] }
    static func getFilePath() -> String {
        UserDefaults.standard.string(forKey: "saveDirectory")! + "/Recording test"
    }
    static func getScreenWithMouse() -> NSScreen? { nil }
    static func showPreview(path: String, image: NSImage?) {}
    static func showNotification(title: String, body: String, id: String) {
        notifications.append((title, body))
    }
}
final class PopoverState {
    static let shared = PopoverState()
    var isPaused = false
}
final class SleepPreventer {
    static let shared = SleepPreventer()
    func preventSleep(reason: String) {}
    func allowSleep() {}
}
final class AppDelegate {
    static let shared = AppDelegate()
    func createNewWindow(view: some View, title: String, only: Bool) {}
}
struct PreviewView: View {
    let frame: NSImage
    let filePath: String
    var body: some View { EmptyView() }
}
struct VideoTrimmerView: View {
    let videoURL: URL
    var body: some View { EmptyView() }
}
var previewWindow: NSWindow { fatalError("Preview UI must not be used in these tests") }
func updateStatusBar() {}
extension String { var local: String { self } }

final class SimulatedSession: AVCaptureSession {
    override var isRunning: Bool { true }
    override func stopRunning() {}
}
final class SimulatedMovieOutput: AVCaptureMovieFileOutput {
    var seconds: Double = 1
    var pauseCalls = 0
    var resumeCalls = 0
    var stopCalls = 0
    var active = false
    var recordingDelegate: AVCaptureFileOutputRecordingDelegate?
    var url: URL?
    var startDelay: Double = 0
    var finishError: NSError?
    var writeFile = true
    override var isRecording: Bool { active }
    override var recordedDuration: CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }
    override func startRecording(to outputFileURL: URL, recordingDelegate: AVCaptureFileOutputRecordingDelegate) {
        url = outputFileURL
        self.recordingDelegate = recordingDelegate
        DispatchQueue.global().asyncAfter(deadline: .now() + startDelay) {
            self.active = true
            recordingDelegate.fileOutput?(self, didStartRecordingTo: outputFileURL, from: [])
        }
    }
    override func stopRecording() {
        stopCalls += 1
        guard active, let url, let recordingDelegate else { return }
        active = false
        if writeFile { try! Data("simulated movie data".utf8).write(to: url) }
        recordingDelegate.fileOutput(self, didFinishRecordingTo: url, from: [], error: finishError)
    }
    override func pauseRecording() { pauseCalls += 1 }
    override func resumeRecording() { resumeCalls += 1 }
}
"""#

let tests = #"""
extension WebcamRecorder {
    static func runTests() {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        UserDefaults.standard.setVolatileDomain([
            "saveDirectory": directory.path,
            "showPreview": false,
            "trimAfterRecord": false
        ], forName: UserDefaults.argumentDomain)
        let recorder = WebcamRecorder()
        func waitUntil(_ message: String, _ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while !condition(), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(condition(), message)
        }
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            print("PASS: \(message)")
        }
        func awaitQueue() {
            var completed = false
            recorder.queue.async { DispatchQueue.main.async { completed = true } }
            waitUntil("serial queue must settle", { completed })
        }
        func launch(_ output: SimulatedMovieOutput, name: String) {
            let url = directory.appendingPathComponent(name).appendingPathExtension("mov")
            recorder.queue.async {
                recorder.captureSession = SimulatedSession()
                recorder.movieOutput = output
                recorder.recordingSettings = RecordingSettings(countdown: 0, encoder: "h264", preventSleep: false, showPreview: false, trimAfterRecord: false, autoStopMinutes: 0)
                recorder.recordingURL = url
                recorder.backendState = .previewing
                recorder.publishState(.previewing)
                recorder.beginFileRecording(output: output, session: recorder.captureSession!, url: url)
            }
            waitUntil("recording must start", { recorder.state == .recording })
        }

        recorder.startPreview(cameraID: "")
        check(recorder.isBusy, "preparation reserves ownership immediately")
        waitUntil("invalid camera must return idle", { recorder.state == .idle && !recorder.isBusy })
        check(recorder.errorMessage == "No camera is selected.", "missing-camera error is recoverable without permissions")
        SCContext.streamType = .screen
        recorder.startPreview(cameraID: "")
        check(!recorder.isBusy && recorder.errorMessage == "Another recording is already active.", "webcam setup cannot take ownership during another recording")
        SCContext.streamType = nil
        WebcamScreenRecorder.shared.isBusy = true
        recorder.errorMessage = nil
        recorder.startPreview(cameraID: "")
        check(!recorder.isBusy && recorder.errorMessage == "Another recording is already active.", "Mode 2 preparation blocks Mode 1 even without an active SCStream")
        WebcamScreenRecorder.shared.isBusy = false

        recorder.queue.async {
            recorder.backendState = .countdown
            recorder.publishState(.countdown)
            recorder.startCountdown(5)
        }
        waitUntil("countdown published", { recorder.state == .countdown })
        recorder.cancelPreview()
        waitUntil("countdown cancelled", { recorder.state == .idle && !recorder.isBusy })
        check(recorder.countdownRemaining == 0, "cancel countdown clears timer and ownership")

        let existing = directory.appendingPathComponent("Recording test.mov")
        try! Data("existing file".utf8).write(to: existing)
        var candidate: URL?
        recorder.queue.async {
            let url = recorder.validatedOutputURL()
            DispatchQueue.main.async { candidate = url }
        }
        waitUntil("output path generated", { candidate != nil })
        check(candidate!.lastPathComponent == "Recording test (1).mov", "MOV output avoids overwriting an existing recording")
        check(try! String(contentsOf: existing, encoding: .utf8) == "existing file", "existing recording bytes remain unchanged")

        let output = SimulatedMovieOutput()
        output.seconds = 15
        launch(output, name: "normal")
        recorder.pauseRecording()
        waitUntil("native pause completed", { recorder.state == .paused })
        check(output.pauseCalls == 1 && recorder.recordedDuration == 15, "pause routes to native output and uses its effective duration")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(recorder.recordedDuration == 15, "paused timer does not include wall-clock time")
        recorder.pauseRecording()
        waitUntil("native resume completed", { recorder.state == .recording })
        check(output.resumeCalls == 1, "resume routes to native output")
        recorder.stopRecording()
        recorder.stopRecording()
        waitUntil("normal recording finished", { recorder.state == .idle && !recorder.isBusy })
        check(output.stopCalls == 1, "repeated stop finalizes only once")
        check(recorder.errorMessage == nil && SCContext.streamType == nil, "successful finish releases shared recording state")

        let again = SimulatedMovieOutput()
        launch(again, name: "second")
        recorder.stopRecording()
        waitUntil("second recording finished", { recorder.state == .idle && !recorder.isBusy })
        recorder.startPreview(cameraID: "")
        waitUntil("preview can restart after file completion", { recorder.state == .idle && recorder.errorMessage == "No camera is selected." })
        check(recorder.backendState == .idle, "file completion resets backend state for the next preview")

        let delayed = SimulatedMovieOutput()
        delayed.startDelay = 0.15
        delayed.seconds = 0
        recorder.queue.async {
            recorder.captureSession = SimulatedSession()
            recorder.movieOutput = delayed
            recorder.recordingSettings = RecordingSettings(countdown: 0, encoder: "h264", preventSleep: false, showPreview: false, trimAfterRecord: false, autoStopMinutes: 0)
            recorder.recordingURL = directory.appendingPathComponent("immediate.mov")
            recorder.backendState = .previewing
            recorder.beginFileRecording(output: delayed, session: recorder.captureSession!, url: recorder.recordingURL!)
        }
        waitUntil("delayed start pending", { recorder.state == .starting })
        recorder.stopRecording()
        waitUntil("stop-before-start finished", { recorder.state == .idle && !recorder.isBusy })
        check(delayed.stopCalls == 1, "stop before didStart is honored after the native start callback")
        check(recorder.errorMessage != nil, "a nonempty zero-duration file is not reported as a completed recording")

        let failure = SimulatedMovieOutput()
        failure.finishError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "encoding failed"])
        launch(failure, name: "failed")
        recorder.stopRecording()
        waitUntil("failed recording finished", { recorder.state == .idle && !recorder.isBusy })
        check(recorder.errorMessage?.contains("encoding failed") == true, "file-output error is not reported as success")

        let warning = SimulatedMovieOutput()
        warning.finishError = NSError(domain: "test", code: 2, userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true])
        launch(warning, name: "warning")
        recorder.stopRecording()
        waitUntil("successful native warning finished", { recorder.state == .idle && !recorder.isBusy })
        check(recorder.errorMessage == nil, "successful-finish metadata accepts a usable native output")

        let interrupted = SimulatedMovieOutput()
        launch(interrupted, name: "interrupted")
        recorder.queue.async { recorder.handleCaptureFailure("The camera was disconnected.") }
        waitUntil("interrupted recording finished", { recorder.state == .idle && !recorder.isBusy })
        check(recorder.errorMessage == "The camera was disconnected.", "a saved partial recording retains its interruption reason")

        let missing = SimulatedMovieOutput()
        missing.writeFile = false
        launch(missing, name: "missing")
        recorder.stopRecording()
        waitUntil("missing output finished", { recorder.state == .idle && !recorder.isBusy })
        check(recorder.errorMessage != nil, "missing output file is never reported as success")
        recorder.stopRecording()
        recorder.pauseRecording()
        awaitQueue()
        check(!recorder.isBusy && recorder.state == .idle, "idle stop and pause are harmless")
        print("All hardware-independent webcam lifecycle tests passed.")
    }
}
WebcamRecorder.runTests()
"""#

let harnessURL = temporaryDirectory.appendingPathComponent("WebcamHarness.swift")
try (fixtures + "\n" + backend + "\n" + tests).write(to: harnessURL, atomically: true, encoding: .utf8)
let executable = temporaryDirectory.appendingPathComponent("WebcamHarness")
func run(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "Command failed: \(arguments)")
}
try run(["swiftc", "-swift-version", "5", harnessURL.path, "-o", executable.path])
let process = Process()
process.executableURL = executable
process.arguments = [temporaryDirectory.path]
try process.run()
process.waitUntilExit()
precondition(process.terminationStatus == 0, "Webcam lifecycle tests failed")
