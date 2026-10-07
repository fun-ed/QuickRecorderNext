import Foundation
import Darwin

let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let productionFile = repositoryRoot.appendingPathComponent("QuickRecorder/RecordEngine.swift")
let productionSource = try String(contentsOf: productionFile, encoding: .utf8)
let helperStart = "// WEBCAM_SCREEN_PURE_HELPERS_BEGIN"
let helperEnd = "// WEBCAM_SCREEN_PURE_HELPERS_END"
guard let startRange = productionSource.range(of: helperStart),
      let endRange = productionSource.range(of: helperEnd),
      startRange.upperBound <= endRange.lowerBound else {
    fatalError("Could not locate WebcamScreenRecorder production helper markers in \(productionFile.path)")
}
let productionHelpers = String(productionSource[startRange.upperBound..<endRange.lowerBound])
let backendStartMarker = "// WEBCAM_SCREEN_BACKEND_BEGIN"
let backendEndMarker = "// WEBCAM_SCREEN_BACKEND_END"
guard let backendStart = productionSource.range(of: backendStartMarker),
      let backendEnd = productionSource.range(of: backendEndMarker),
      backendStart.upperBound <= backendEnd.lowerBound else {
    fatalError("Could not locate WebcamScreenRecorder production backend markers in \(productionFile.path)")
}
let productionBackend = String(productionSource[backendStart.upperBound..<backendEnd.lowerBound])
let audioHelperStart = "extension AVAudioPCMBuffer {"
let audioHelperEnd = "// MARK: - Webcam + screen deterministic logic"
guard let audioStart = productionSource.range(of: audioHelperStart),
      let audioEnd = productionSource.range(of: audioHelperEnd),
      audioStart.upperBound <= audioEnd.lowerBound else {
    fatalError("Could not locate production PCM sample-buffer helper in \(productionFile.path)")
}
let productionAudioSampleBufferHelper = String(productionSource[audioStart.lowerBound..<audioEnd.lowerBound])

let runner = #"""
import AppKit
import AVFoundation
import AVFAudio
import Combine
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import VideoToolbox
import Darwin

extension String {
    var local: String { self }
}

enum StreamType: Equatable {
    case screen
}

enum VideoFormat: String {
    case mp4
    case mov
}

enum Encoder: String {
    case h264
    case h265
}

final class WebcamRecorder {
    static let shared = WebcamRecorder()
    enum State: Equatable {
        case idle, preparing, previewing, countdown, starting, recording, paused, finishing
    }
    var isBusy = false
}

enum SCContext {
    static var streamType: StreamType?
    static var screen: SCDisplay?
    static var filePath = ""
    static var autoStop = 0
    static var isPaused = false
    static var timePassed: TimeInterval = 0
    static var startTime: Date?

    static func getCameras() -> [AVCaptureDevice] { [] }
    static func getMicrophone() -> [AVCaptureDevice] { [] }
    static func getFilePath() -> String { NSTemporaryDirectory() + "Recording at Offline Test" }
    static func showPreview(path: String, image: NSImage) {}
    static func showNotification(title: String, body: String, id: String) {}
}

final class SleepPreventer {
    static let shared = SleepPreventer()
    func preventSleep(reason: String) {}
    func allowSleep() {}
}

final class PopoverState {
    static let shared = PopoverState()
    var isPaused = false
}

struct VideoTrimmerView {
    let videoURL: URL
}

final class AppDelegate {
    static let shared = AppDelegate()
    func createNewWindow<View>(view: View, title: String, only: Bool) {}
}

func updateStatusBar() {}

\#(productionAudioSampleBufferHelper)
\#(productionHelpers)
\#(productionBackend)

struct TestPixel {
    let b: UInt8
    let g: UInt8
    let r: UInt8
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
}

func pixelBuffer(width: Int, height: Int, color: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CVPixelBuffer {
    let attributes: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
    ]
    var result: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &result
    )
    check(status == kCVReturnSuccess, "create synthetic BGRA pixel buffer")
    guard let result, CVPixelBufferLockBaseAddress(result, []) == kCVReturnSuccess,
          let base = CVPixelBufferGetBaseAddress(result)?.assumingMemoryBound(to: UInt8.self) else {
        fatalError("Could not lock synthetic pixel buffer")
    }
    defer { CVPixelBufferUnlockBaseAddress(result, []) }
    let rowBytes = CVPixelBufferGetBytesPerRow(result)
    for y in 0..<height {
        for x in 0..<width {
            let (b, g, r, a) = color(x, y)
            let offset = y * rowBytes + x * 4
            base[offset] = b
            base[offset + 1] = g
            base[offset + 2] = r
            base[offset + 3] = a
        }
    }
    return result
}

func solidBuffer(width: Int, height: Int, b: UInt8, g: UInt8, r: UInt8) -> CVPixelBuffer {
    pixelBuffer(width: width, height: height) { _, _ in (b, g, r, 255) }
}

func splitCameraBuffer(inverted: Bool = false) -> CVPixelBuffer {
    pixelBuffer(width: 160, height: 90) { x, _ in
        let leftIsRed = x < 80
        let red = inverted ? !leftIsRed : leftIsRed
        return red ? (0, 0, 255, 255) : (0, 255, 0, 255)
    }
}

func readPixel(_ buffer: CVPixelBuffer, x: Int, rawY: Int) -> TestPixel {
    check(CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess, "lock output pixel buffer")
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
        fatalError("Output pixel buffer has no base address")
    }
    let safeX = min(max(0, x), CVPixelBufferGetWidth(buffer) - 1)
    let safeY = min(max(0, rawY), CVPixelBufferGetHeight(buffer) - 1)
    let offset = safeY * CVPixelBufferGetBytesPerRow(buffer) + safeX * 4
    return TestPixel(b: base[offset], g: base[offset + 1], r: base[offset + 2])
}

func isRed(_ pixel: TestPixel) -> Bool {
    pixel.r > 110 && Int(pixel.r) > Int(pixel.g) * 3 / 2 && Int(pixel.r) > Int(pixel.b) * 3 / 2
}

func isGreen(_ pixel: TestPixel) -> Bool {
    pixel.g > 110 && Int(pixel.g) > Int(pixel.r) * 3 / 2 && Int(pixel.g) > Int(pixel.b) * 3 / 2
}

func isBlue(_ pixel: TestPixel) -> Bool {
    pixel.b > 110 && Int(pixel.b) > Int(pixel.r) * 3 / 2 && Int(pixel.b) > Int(pixel.g) * 3 / 2
}

func checkPureLogic() {
    let capped = WebcamScreenOutputSize.capped(width: 3840, height: 2160)
    check(capped == WebcamScreenOutputSize(width: 1920, height: 1080), "output size is capped to 1920x1080")
    let odd = WebcamScreenOutputSize.capped(width: 1921, height: 1081)
    check(odd != nil && odd!.width.isMultiple(of: 2) && odd!.height.isMultiple(of: 2), "capped dimensions are even")
    check(odd!.width <= 1920 && odd!.height <= 1080, "capped dimensions respect codec limits")
    check(WebcamScreenOutputSize.capped(width: 15, height: 100) == nil, "reject dimensions below minimum codec size")

    let canvas = CGSize(width: 320, height: 180)
    for position in WebcamScreenLayout.Position.allCases {
        let layout = WebcamScreenLayout(position: position, widthFraction: 0.3)
        let rect = layout.rect(in: canvas)
        check(!rect.isEmpty && rect.minX >= 0 && rect.minY >= 0, "PiP rect is non-empty and inside canvas for \(position)")
        check(rect.maxX <= canvas.width && rect.maxY <= canvas.height, "PiP rect stays inside canvas for \(position)")
        check(abs(rect.width / rect.height - 16.0 / 9.0) < 0.0001, "PiP aspect ratio is 16:9 for \(position)")
        let expectedX = position == .topLeft || position == .bottomLeft ? 4.5 : canvas.width - 4.5 - rect.width
        let expectedY = position == .bottomLeft || position == .bottomRight ? 4.5 : canvas.height - 4.5 - rect.height
        check(abs(rect.minX - expectedX) < 0.001 && abs(rect.minY - expectedY) < 0.001, "PiP corner placement uses consistent margin for \(position)")
    }

    var timeline = WebcamScreenTimeline()
    timeline.start(at: 100)
    check(timeline.elapsed(at: 102) == 2, "active elapsed time before pauses")
    timeline.pause(at: 103)
    check(timeline.elapsed(at: 106) == 3 && timeline.isPaused(at: 105), "first pause freezes elapsed time")
    timeline.resume(at: 108)
    check(timeline.elapsed(at: 110) == 5 && timeline.isPaused(at: 105), "first pause remains identifiable after resume")
    timeline.pause(at: 111)
    check(timeline.elapsed(at: 112) == 6 && timeline.isPaused(at: 112), "second pause shares the same time origin")
    timeline.resume(at: 114)
    check(timeline.elapsed(at: 120) == 12, "multiple pause durations are subtracted")
    check(timeline.isPaused(at: 112) && !timeline.isPaused(at: 115), "all historical pause intervals are retained")
    check(timeline.elapsed(at: 102) == 2 && timeline.elapsed(at: 120) == 12, "historical and live media timestamps share the host-origin pause adjustment")

    var pts = WebcamScreenMonotonicPTS()
    check(pts.accept(0) && pts.accept(1.0 / 30.0), "accept increasing video PTS")
    check(!pts.accept(1.0 / 30.0) && !pts.accept(0.02), "skip duplicate and out-of-order output PTS")
    check(pts.accept(2.0 / 30.0), "resume output after skipped timer tick")

    var recent = WebcamScreenRecentBuffer<Int>(capacity: 4)
    for value in 0..<6 { recent.append(value, at: Double(value)) }
    check(recent.values.count == 4 && recent.values.first?.value == 2, "camera history is bounded")
    check(recent.latest(notAfter: 4.5)?.value == 4, "select latest camera sample not newer than timer timestamp")
    check(recent.latest(notAfter: 1.5) == nil, "do not select a camera sample newer than timer timestamp")

    var backpressure = WebcamScreenBackpressure(timeout: 5)
    check(!backpressure.timedOut(isReady: false, at: 10), "start backpressure timeout")
    check(!backpressure.timedOut(isReady: false, at: 14.9), "do not time out before limit")
    check(backpressure.timedOut(isReady: false, at: 15), "time out sustained writer backpressure")
    check(!backpressure.timedOut(isReady: true, at: 16) && backpressure.blockedSince == nil, "ready writer resets backpressure")
}

func isNone<Value>(_ value: Value?) -> Bool {
    if case .none = value { return true }
    return false
}

func checkPendingScreenStartup() {
    var pending = WebcamScreenPendingFrame<Int>()
    pending.holdComplete(41)
    pending.ignoreIdle()
    check(pending.value == 41, "screen idle status preserves a complete frame received before the stream clock")
    var cachedFrame: Int?
    if let replay = pending.takeWhenClockReady() {
        cachedFrame = replay
    }
    check(cachedFrame == 41, "clock readiness replays the early complete screen frame so a static desktop can render")
    check(pending.value == nil, "replayed complete frame leaves no duplicate pending sample")
    pending.holdComplete(1)
    pending.holdComplete(2)
    check(pending.value == 2, "pre-clock screen buffering remains bounded to one latest complete sample")
    pending.clear()
    check(pending.value == nil, "screen reconfiguration clears its pending complete sample")
}

func audioSample(pts: Double, dts: Double? = nil, sampleCount: Int = 4_800) -> CMSampleBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
    pcm.frameLength = AVAudioFrameCount(sampleCount)
    if let channels = pcm.floatChannelData {
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<sampleCount { channels[channel][frame] = 0 }
        }
    }
    guard let raw = pcm.asSampleBuffer else { fatalError("Production PCM conversion returned no sample buffer") }
    let timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 48_000),
        presentationTimeStamp: CMTime(seconds: pts, preferredTimescale: 1_000_000),
        decodeTimeStamp: dts.map { CMTime(seconds: $0, preferredTimescale: 1_000_000) } ?? .invalid
    )
    var timed: CMSampleBuffer?
    var timings = [timing]
    let status = timings.withUnsafeBufferPointer { buffer in
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: raw,
            sampleTimingEntryCount: CMItemCount(buffer.count),
            sampleTimingArray: buffer.baseAddress!,
            sampleBufferOut: &timed
        )
    }
    check(status == noErr, "retime synthetic PCM sample")
    guard let timed else { fatalError("Could not create timestamped PCM sample") }
    check(CMSampleBufferMakeDataReady(timed) == noErr, "make synthetic PCM sample data ready")
    return timed
}

func checkAdjustedAudioSamples(recorder: WebcamScreenRecorder) {
    let hostClock = CMClockGetHostTimeClock()
    let base = CMTimeGetSeconds(CMClockGetTime(hostClock))
    var timeline = WebcamScreenTimeline()
    timeline.start(at: base)
    timeline.pause(at: base + 1)
    timeline.resume(at: base + 2)
    timeline.pause(at: base + 3)
    timeline.resume(at: base + 4)
    recorder._testSetTimeline(timeline)

    check(isNone(recorder._testAdjustedAudioSample(audioSample(pts: base - 0.1), sourceClock: hostClock)), "drop audio before the shared writer origin")
    for pts in [base + 0.95, base + 2.95] {
        check(isNone(recorder._testAdjustedAudioSample(audioSample(pts: pts), sourceClock: hostClock)), "drop audio starting before a pause but ending inside it")
    }
    for pts in [base + 1, base + 1.95, base + 3, base + 3.95] {
        check(isNone(recorder._testAdjustedAudioSample(audioSample(pts: pts), sourceClock: hostClock)), "drop paused audio and buffers overlapping either pause boundary")
    }
    check(isNone(recorder._testAdjustedAudioSample(audioSample(pts: base + 5.1, dts: base + 3.95), sourceClock: hostClock)), "drop an audio buffer whose decode timestamp overlaps a pause")

    guard let first = recorder._testAdjustedAudioSample(audioSample(pts: base + 5.1, dts: base + 5.0), sourceClock: hostClock) else {
        fatalError("Production audio timestamp adjustment rejected a valid post-pause sample")
    }
    check(abs(first.1 - 3.1) < 0.002, "first post-pause audio PTS shares the same two-pause offset as video")
    let firstDTS = CMTimeGetSeconds(CMSampleBufferGetDecodeTimeStamp(first.0))
    check(abs(firstDTS - 3.0) < 0.002, "decode timestamp is converted to host time and adjusted by the same origin and pause intervals")
    let firstDuration = CMTimeGetSeconds(CMSampleBufferGetDuration(first.0))
    check(firstDuration > 0.09 && firstDuration < 0.11, "audio buffer duration survives production timestamp copying")
    let firstEnd = first.1 + firstDuration

    guard let delayed = recorder._testAdjustedAudioSample(audioSample(pts: base + 0.5), sourceClock: hostClock),
          let next = recorder._testAdjustedAudioSample(audioSample(pts: base + 5.3, dts: base + 5.2), sourceClock: hostClock) else {
        fatalError("Production audio timestamp adjustment rejected a delayed or later valid sample")
    }
    check(abs(delayed.1 - 0.5) < 0.002, "a late historical callback is not shifted by future pause durations")
    check(abs(next.1 - 3.3) < 0.002 && next.1 >= firstEnd, "later adjusted audio buffer starts monotonically after the previous buffer end")
    var monotonic = WebcamScreenMonotonicPTS()
    check(monotonic.accept(first.1), "append the first adjusted audio PTS")
    check(!monotonic.accept(delayed.1), "drop a delayed out-of-order audio callback")
    check(monotonic.accept(next.1), "accept monotonic audio after backpressure or skipped callbacks")
    check(abs((timeline.elapsed(at: base + 5.1) ?? -1) - first.1) < 0.002, "video timer and actual adjusted audio use the same production timeline")
}

func pumpMainRunLoop(until condition: () -> Bool, timeout: TimeInterval, message: String) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    check(condition(), message)
}

func checkLifecycle() {
    let recorder = WebcamScreenRecorder.shared
    WebcamRecorder.shared.isBusy = false
    SCContext.streamType = nil
    recorder._testSetState(.idle)
    let initialLayout = WebcamScreenLayout(position: .topLeft, widthFraction: 0.32, mirrored: true)
    recorder.updateLayout(initialLayout)
    recorder._testFlushQueue()
    let storedLayout = recorder._testLayout()
    check(storedLayout.position == .topLeft && storedLayout.widthFraction == 0.32 && storedLayout.mirrored, "initial layout is applied while idle")

    recorder.pauseRecording()
    recorder.stopRecording()
    recorder.cancelPreview()
    recorder.startRecording()
    recorder._testFlushQueue()
    check(recorder._testBackendState() == .idle && recorder.state == .idle, "idle controls are idempotent")

    recorder.startPreview(cameraID: "", displayID: 0, captureSystemAudio: false)
    check(recorder.state == .preparing && recorder.isBusy, "startPreview reserves busy state synchronously before asynchronous setup")
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "empty camera preparation should recover to idle")
    check(recorder.errorMessage == "No camera is selected.", "empty camera failure is recoverable without requesting camera permission")

    recorder.startPreview(cameraID: "", displayID: 0, captureSystemAudio: false)
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "repeated empty-camera session should recover")
    check(recorder.errorMessage == "No camera is selected.", "backend can start a new session after preparation failure")

    WebcamRecorder.shared.isBusy = true
    recorder.startPreview(cameraID: "", displayID: 0, captureSystemAudio: false)
    check(recorder.state == .idle && !recorder.isBusy && recorder.errorMessage == "Another recording is already active.", "another backend's busy reservation blocks webcam preview")
    WebcamRecorder.shared.isBusy = false
    SCContext.streamType = .screen
    recorder.startPreview(cameraID: "", displayID: 0, captureSystemAudio: false)
    check(recorder.state == .idle && recorder.errorMessage == "Another recording is already active.", "an existing shared recording blocks webcam preview")
    SCContext.streamType = nil

    recorder._testSetState(.previewing)
    recorder.startPreview(cameraID: "", displayID: 0, captureSystemAudio: false)
    check(recorder.state == .preparing && recorder.isBusy, "the owning preview may reconfigure its source")
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "reconfigured empty-camera preview should cleanly fail")
    check(recorder.errorMessage == "No camera is selected.", "own-source reconfiguration does not trip the other-backend guard")

    let lockedLayout = recorder._testLayout()
    recorder._testSetState(.countdown)
    recorder.updateLayout(WebcamScreenLayout(position: .bottomLeft, widthFraction: 0.5, mirrored: false))
    recorder._testFlushQueue()
    let duringCountdown = recorder._testLayout()
    check(duringCountdown.position == lockedLayout.position && duringCountdown.widthFraction == lockedLayout.widthFraction && duringCountdown.mirrored == lockedLayout.mirrored, "layout is locked while countdown is active")
    recorder.cancelPreview()
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "countdown cancellation should release the session")

    recorder._testSetState(.recording)
    recorder.updateLayout(WebcamScreenLayout(position: .bottomRight, widthFraction: 0.5, mirrored: false))
    recorder.startPreview(cameraID: "", displayID: 0, captureSystemAudio: false)
    recorder._testFlushQueue()
    let duringRecording = recorder._testLayout()
    check(recorder.state == .recording && duringRecording.position == lockedLayout.position && duringRecording.widthFraction == lockedLayout.widthFraction && duringRecording.mirrored == lockedLayout.mirrored, "source and layout changes are locked during recording")
    recorder._testSetState(.idle)

    recorder._testSetState(.preparing)
    recorder.stopRecording()
    recorder.stopRecording()
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "stopRecording cancels setup and tolerates duplicate stop")
    recorder._testSetState(.previewing)
    recorder.cancelPreview()
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "cancelPreview closes a ready preview")

    recorder._testSetState(.starting)
    recorder.cancelPreview()
    recorder._testFlushQueue()
    check(recorder.state == .starting && recorder.isBusy, "cancelPreview does not abandon writer startup")
    recorder.stopRecording()
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "stopRecording cancels startup without an open writer")

    recorder._testSetState(.recording)
    recorder.pauseRecording()
    pumpMainRunLoop(until: { recorder.state == .paused }, timeout: 5, message: "recording can pause")
    check(recorder.isPaused, "published pause state follows backend timeline")
    recorder.pauseRecording()
    pumpMainRunLoop(until: { recorder.state == .recording }, timeout: 5, message: "pause control resumes recording")
    check(!recorder.isPaused, "published pause state clears on resume")
    recorder._testSetState(.paused)
    recorder.stopRecording()
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "stopRecording accepts paused sessions")

    recorder._testSetState(.previewing)
    recorder._testQueueBackendTransition(.countdown)
    recorder.startPreview(cameraID: "", displayID: 0, captureSystemAudio: false)
    check(recorder.state == .preparing && recorder.isBusy, "queued reconfiguration first reserves its published generation")
    pumpMainRunLoop(
        until: { recorder.state == .countdown && recorder.errorMessage == "Another recording is already active." },
        timeout: 5,
        message: "queued countdown transition must reject a stale preview reconfiguration and restore actual state"
    )
    check(recorder._testBackendState() == .countdown && recorder.isBusy, "rejected reconfiguration preserves the active backend generation")
    recorder.stopRecording()
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 5, message: "queued-start race cleanup")
    recorder._testSetState(.idle)
}

func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter, message: String) {
    let deadline = Date().addingTimeInterval(10)
    while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.001)
    }
    check(input.isReadyForMoreMediaData, message)
}

func writeSyntheticRemuxSource(url: URL, audioTrackCount: Int) throws -> AVVideoCodecType {
    let width = 160
    let height = 90
    let writer = try AVAssetWriter(outputURL: url, fileType: url.pathExtension == "mp4" ? .mp4 : .mov)
    var codec = AVVideoCodecType.hevc
    var videoSettings: [String: Any] = [
        AVVideoCodecKey: codec,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 500_000]
    ]
    if !writer.canApply(outputSettings: videoSettings, forMediaType: .video) {
        codec = .h264
        videoSettings[AVVideoCodecKey] = codec
    }
    check(writer.canApply(outputSettings: videoSettings, forMediaType: .video), "synthetic source video codec is supported")
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoInput,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
    )
    check(writer.canAdd(videoInput), "add synthetic video input")
    writer.add(videoInput)

    var audioInputs = [AVAssetWriterInput]()
    let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 96_000
    ]
    for _ in 0..<audioTrackCount {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = false
        check(writer.canApply(outputSettings: audioSettings, forMediaType: .audio) && writer.canAdd(input), "add synthetic AAC audio input")
        writer.add(input)
        audioInputs.append(input)
    }
    check(writer.startWriting(), "start synthetic multi-track source writer")
    writer.startSession(atSourceTime: .zero)

    let screen = solidBuffer(width: width, height: height, b: 0, g: 0, r: 80)
    for frame in 0..<30 {
        waitUntilReady(videoInput, writer: writer, message: "synthetic video writer input readiness")
        check(adaptor.append(screen, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)), "append synthetic video frame")
    }
    for chunk in 0..<10 {
        let sample = audioSample(pts: Double(chunk) / 10)
        for input in audioInputs {
            waitUntilReady(input, writer: writer, message: "synthetic AAC writer input readiness")
            check(input.append(sample), "append synthetic AAC sample")
        }
    }
    videoInput.markAsFinished()
    audioInputs.forEach { $0.markAsFinished() }
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    check(finished.wait(timeout: .now() + 30) == .success, "finish synthetic multi-track source")
    check(writer.status == .completed, "synthetic multi-track source completes: \(writer.error?.localizedDescription ?? "no error")")
    return codec
}

func checkAudioRemux(temporaryDirectory: URL, fileExtension: String) throws {
    let recorder = WebcamScreenRecorder.shared
    let sourceURL = temporaryDirectory.appendingPathComponent("multitrack-source-\(UUID().uuidString).\(fileExtension)")
    let outputURL = temporaryDirectory.appendingPathComponent("mixed-output-\(UUID().uuidString).\(fileExtension)")
    let sourceCodec = try writeSyntheticRemuxSource(url: sourceURL, audioTrackCount: 2)
    let sourceAsset = AVURLAsset(url: sourceURL)
    let sourceVideo = sourceAsset.tracks(withMediaType: .video)
    let sourceAudio = sourceAsset.tracks(withMediaType: .audio)
    check(sourceVideo.count == 1 && sourceAudio.count == 2, "synthetic source contains one video and two AAC tracks")
    guard let sourceDescription = sourceVideo[0].formatDescriptions.first else {
        fatalError("Synthetic source video format description is unavailable")
    }
    let sourceSubtype = CMFormatDescriptionGetMediaSubType(sourceDescription as! CMFormatDescription)
    check(sourceSubtype == (sourceCodec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264), "synthetic video source uses its selected codec")

    recorder._testStartRemux(sourceURL: sourceURL, outputURL: outputURL, fileExtension: fileExtension)
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 120, message: "production audio-only mix plus passthrough remux should finish")
    check(FileManager.default.fileExists(atPath: outputURL.path), "production remux creates a final \(fileExtension): \(recorder.errorMessage ?? "no reported error")")
    check(!FileManager.default.fileExists(atPath: sourceURL.path), "successful remux removes the raw intermediate only after final export")
    let finalAsset = AVURLAsset(url: outputURL)
    let finalVideo = finalAsset.tracks(withMediaType: .video)
    let finalAudio = finalAsset.tracks(withMediaType: .audio)
    check(finalVideo.count == 1 && finalAudio.count == 1, "remux outputs exactly one video and one mixed audio track")
    guard let finalDescription = finalVideo[0].formatDescriptions.first else {
        fatalError("Remuxed video format description is unavailable")
    }
    check(CMFormatDescriptionGetMediaSubType(finalDescription as! CMFormatDescription) == sourceSubtype, "passthrough mux preserves the selected source video codec")
    check(finalAsset.duration.seconds >= 0.85 && finalAsset.duration.seconds <= 1.2, "remuxed \(fileExtension) retains approximately one-second duration")

    let visibleRawURL = temporaryDirectory.appendingPathComponent("visible-raw-\(UUID().uuidString).\(fileExtension).\(fileExtension).\(fileExtension)")
    let failedOutputURL = temporaryDirectory.appendingPathComponent("must-not-exist-\(UUID().uuidString).\(fileExtension)")
    _ = try writeSyntheticRemuxSource(url: visibleRawURL, audioTrackCount: 1)
    recorder._testStartRemux(sourceURL: visibleRawURL, outputURL: failedOutputURL, fileExtension: fileExtension)
    pumpMainRunLoop(until: { recorder.state == .idle }, timeout: 30, message: "remux failure should settle to a preserved raw recording")
    check(FileManager.default.fileExists(atPath: visibleRawURL.path), "failed remux preserves its original multi-track source")
    check(!visibleRawURL.lastPathComponent.hasPrefix("."), "failed remux raw file is visible and orphan-scannable")
    check(!FileManager.default.fileExists(atPath: failedOutputURL.path), "failed remux does not leave an incomplete final output")
    check(recorder.errorMessage?.contains(visibleRawURL.path) == true, "remux warning identifies the preserved raw recording")
    let reservationFiles = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        .filter { $0.hasSuffix(".quickrecorder-reserve") }
    check(reservationFiles.isEmpty, "remux success and fallback remove all temporary reservation markers")
}

func render(
    compositor: WebcamScreenCompositor,
    screen: CVPixelBuffer,
    camera: CVPixelBuffer,
    layout: WebcamScreenLayout,
    size: CGSize
) -> CVPixelBuffer {
    guard let image = compositor.compositeImage(screen: screen, camera: camera, layout: layout, outputSize: size) else {
        fatalError("Production compositor returned no image")
    }
    var output: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        Int(size.width),
        Int(size.height),
        kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary,
        &output
    )
    check(status == kCVReturnSuccess, "create composited output buffer")
    guard let output else { fatalError("No composited output buffer") }
    compositor.render(image, into: output, outputSize: size)
    return output
}

func checkCompositorAndWriter(temporaryDirectory: URL) throws {
    let width = 320
    let height = 180
    let size = CGSize(width: CGFloat(width), height: CGFloat(height))
    let compositor = WebcamScreenCompositor()
    let screen = solidBuffer(width: width, height: height, b: 255, g: 0, r: 0)
    let camera = splitCameraBuffer()
    let bottomRight = WebcamScreenLayout(position: .bottomRight, widthFraction: 0.35)
    let calibration = render(compositor: compositor, screen: screen, camera: camera, layout: bottomRight, size: size)
    let calibrationRect = bottomRight.rect(in: size)
    let calibrationX = Int((calibrationRect.minX + calibrationRect.width * 0.25).rounded())
    let calibrationY = Int(calibrationRect.midY.rounded())
    let direct = readPixel(calibration, x: calibrationX, rawY: calibrationY)
    let flipped = readPixel(calibration, x: calibrationX, rawY: height - 1 - calibrationY)
    check(isRed(direct) != isRed(flipped), "calibrate Core Image pixel-buffer row orientation")
    let ciYUsesSameRawRow = isRed(direct)
    func sample(_ buffer: CVPixelBuffer, x: CGFloat, ciY: CGFloat) -> TestPixel {
        let rawY = Int(ciY.rounded())
        return readPixel(buffer, x: Int(x.rounded()), rawY: ciYUsesSameRawRow ? rawY : height - 1 - rawY)
    }

    for position in WebcamScreenLayout.Position.allCases {
        let layout = WebcamScreenLayout(position: position, widthFraction: 0.35)
        let output = render(compositor: compositor, screen: screen, camera: camera, layout: layout, size: size)
        let rect = layout.rect(in: size)
        let red = sample(output, x: rect.minX + rect.width * 0.25, ciY: rect.midY)
        let green = sample(output, x: rect.minX + rect.width * 0.75, ciY: rect.midY)
        let background = sample(output, x: size.width / 2, ciY: size.height / 2)
        check(isRed(red) && isGreen(green), "camera PiP pixels render at \(position)")
        check(isBlue(background), "static screen remains underneath PiP at \(position)")
    }

    let mirroredLayout = WebcamScreenLayout(position: .bottomRight, widthFraction: 0.35, mirrored: true)
    let mirrored = render(compositor: compositor, screen: screen, camera: camera, layout: mirroredLayout, size: size)
    let mirroredRect = mirroredLayout.rect(in: size)
    check(isGreen(sample(mirrored, x: mirroredRect.minX + mirroredRect.width * 0.25, ciY: mirroredRect.midY)), "mirroring swaps camera left/right pixels")
    check(isRed(sample(mirrored, x: mirroredRect.minX + mirroredRect.width * 0.75, ciY: mirroredRect.midY)), "mirroring preserves opposite camera side")

    let inverseCamera = splitCameraBuffer(inverted: true)
    let nextComposite = render(compositor: compositor, screen: screen, camera: inverseCamera, layout: bottomRight, size: size)
    let rect = bottomRight.rect(in: size)
    check(isRed(sample(calibration, x: rect.minX + rect.width * 0.25, ciY: rect.midY)), "initial camera view is present over a static screen")
    check(isGreen(sample(nextComposite, x: rect.minX + rect.width * 0.25, ciY: rect.midY)), "camera updates while screen buffer is unchanged")
    check(isBlue(sample(calibration, x: size.width / 2, ciY: size.height / 2)) && isBlue(sample(nextComposite, x: size.width / 2, ciY: size.height / 2)), "static screen buffer is reused without changing its pixels")

    let pool = WebcamScreenCompositor.makePixelBufferPool(width: width, height: height)
    check(pool != nil, "production pixel buffer pool helper creates a render pool")

    for (fileType, extensionName) in [(AVFileType.mov, "mov"), (.mp4, "mp4")] {
        let outputURL = temporaryDirectory.appendingPathComponent("webcam-screen-\(UUID().uuidString).\(extensionName)")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_000_000]
        ]
        check(writer.canApply(outputSettings: settings, forMediaType: .video), "H.264 output settings are supported for \(extensionName)")
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        check(writer.canAdd(input), "add a single video input for \(extensionName)")
        writer.add(input)
        check(writer.startWriting(), "start AVAssetWriter for \(extensionName)")
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            let frameBuffer = render(compositor: compositor, screen: screen, camera: camera, layout: bottomRight, size: size)
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            check(input.isReadyForMoreMediaData, "writer input becomes ready for frame \(frame)")
            check(adaptor.append(frameBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)), "append production-composited frame \(frame)")
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        check(finished.wait(timeout: .now() + 30) == .success, "finish \(extensionName) writer")
        check(writer.status == .completed, "writer completed \(extensionName): \(writer.error?.localizedDescription ?? "no error")")

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)
        check(videoTracks.count == 1 && audioTracks.isEmpty, "export has one video track and no unintended audio track for \(extensionName)")
        let duration = asset.duration.seconds
        check(duration.isFinite && duration >= 0.85 && duration <= 1.2, "exported \(extensionName) duration is approximately one second (\(duration))")
        check(abs(videoTracks[0].naturalSize.width) == CGFloat(width) && abs(videoTracks[0].naturalSize.height) == CGFloat(height), "exported \(extensionName) dimensions match compositor output")

        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(
            track: videoTracks[0],
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        check(reader.canAdd(trackOutput), "create decoded video reader for \(extensionName)")
        reader.add(trackOutput)
        check(reader.startReading(), "start decoding \(extensionName)")
        guard let decodedSampleBuffer = trackOutput.copyNextSampleBuffer(),
              let decoded = CMSampleBufferGetImageBuffer(decodedSampleBuffer) else {
            fatalError("Could not decode a frame from \(extensionName) output: \(reader.error?.localizedDescription ?? "no error")")
        }
        let outputRect = bottomRight.rect(in: size)
        let decodedPip = sample(decoded, x: outputRect.minX + outputRect.width * 0.25, ciY: outputRect.midY)
        let decodedBackground = sample(decoded, x: size.width / 2, ciY: size.height / 2)
        check(isRed(decodedPip) && isBlue(decodedBackground), "decoded \(extensionName) retains PiP and screen pixels")
        reader.cancelReading()
    }
}

checkPureLogic()
checkPendingScreenStartup()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("quickrecorder-webcam-screen-verify-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
checkLifecycle()
checkAdjustedAudioSamples(recorder: WebcamScreenRecorder.shared)
for fileExtension in ["mov", "mp4"] {
    try checkAudioRemux(temporaryDirectory: scratch, fileExtension: fileExtension)
}
try checkCompositorAndWriter(temporaryDirectory: scratch)
print("Webcam + Screen offline lifecycle, timeline, pending-frame, compositor, audio-remux, and MOV/MP4 writer checks passed.")
"""#

let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("quickrecorder-webcam-screen-harness-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
let runnerURL = temporaryDirectory.appendingPathComponent("verify.swift")
try runner.write(to: runnerURL, atomically: true, encoding: .utf8)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", "-DWEBCAM_SCREEN_TESTING", runnerURL.path]
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    exit(process.terminationStatus)
}
