//
//  AVContext.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/27.
//
import AppKit
import Foundation
import AVFoundation
import UserNotifications
import Combine
import SwiftUI
import VideoToolbox

extension AppDelegate {
    func recordingCamera(with device: AVCaptureDevice) {
        SCContext.captureSession = AVCaptureSession()
        
        guard let input = try? AVCaptureDeviceInput(device: device),
              SCContext.captureSession.canAddInput(input) else {
            print("Failed to set up camera")
            SCContext.requestCameraPermission()
            return
        }
        SCContext.captureSession.addInput(input)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: .global())
        
        if SCContext.captureSession.canAddOutput(videoOutput) {
            SCContext.captureSession.addOutput(videoOutput)
        }
        
        SCContext.captureSession.startRunning()
        DispatchQueue.main.async { self.startCameraOverlayer() }
    }
    
    func closeCamera() {
        if SCContext.isCameraRunning() {
            //SCContext.previewType = nil
            if camWindow.isVisible { camWindow.close() }
            SCContext.captureSession.stopRunning()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        /* 保留后续以作他用
        if !SCContext.isPaused && ud.string(forKey: "recordCam") != "" {
            if sampleBuffer.isValid { SCContext.isCameraReady = true }
            if sampleBuffer.imageBuffer != nil { SCContext.frameCache = sampleBuffer }
        }*/
    }
}

class AVOutputClass: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = AVOutputClass()
    var output: AVCaptureMovieFileOutput!
    var dataOutput: AVCaptureVideoDataOutput!
    //var captureSession: AVCaptureSession!
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print(sampleBuffer.nsImage?.size)
    }
    
    public func startRecording(with device: AVCaptureDevice, mute: Bool = false, preset: AVCaptureSession.Preset = .high, didOutput: Bool = true) {
        output = AVCaptureMovieFileOutput()
        dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: .global())
        SCContext.captureSession = AVCaptureSession()
        SCContext.previewSession = AVCaptureSession()
        SCContext.captureSession.sessionPreset = preset
        SCContext.previewSession.sessionPreset = preset
        
        guard let input = try? AVCaptureDeviceInput(device: device),
              let preview = try? AVCaptureDeviceInput(device: device),
              SCContext.captureSession.canAddInput(input),
              SCContext.previewSession.canAddInput(preview),
              SCContext.captureSession.canAddOutput(output),
              SCContext.previewSession.canAddOutput(dataOutput) else {
            print("Failed to set up camera or device")
            SCContext.requestCameraPermission()
            return
        }
        
        SCContext.captureSession.addInput(input)
        SCContext.captureSession.addOutput(output)
        SCContext.previewSession.addInput(preview)
        SCContext.previewSession.addOutput(dataOutput)
        
        if mute {
            if let audioConnection = output.connection(with: .audio) {
                SCContext.captureSession.removeConnection(audioConnection)
                /*DispatchQueue.main.async {
                    let alert = createAlert(title: "No Audio Connection",
                                                               message: "Unable to get audio stream on this device, only screen content will be recorded!",
                                                               button1: "OK")
                    alert.runModal()
                }*/
            }
        }
        
        if didOutput {
            let encoderIsH265 = ud.string(forKey: "encoder") == Encoder.h265.rawValue
            let videoSettings: [String: Any] = [ AVVideoCodecKey: encoderIsH265 ? AVVideoCodecType.hevc : AVVideoCodecType.h264 ]
            guard let connection = output.connection(with: .video) else { return }
            output.setOutputSettings(videoSettings, for: connection)
            let fileEnding = ud.string(forKey: "videoFormat") ?? ""
            SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding)"
            SCContext.captureSession.startRunning()
            output.startRecording(to: SCContext.filePath.url, recordingDelegate: self)
            SCContext.streamType = StreamType.idevice
            SCContext.startTime = Date.now
        }
        
        SCContext.previewSession.startRunning()
        DispatchQueue.main.async {
            closeAllWindow(except: "Area Overlayer".local)
            updateStatusBar()
            AppDelegate.shared.startDeviceOverlayer(size: NSSize(width: 300, height: 500))
        }
    }

    public func stopRecording() {
        if SCContext.captureSession.isRunning {
            output.stopRecording()
            SCContext.captureSession.stopRunning()
            SCContext.previewSession.stopRunning()
            SCContext.streamType = nil
            SCContext.startTime = nil
            DispatchQueue.main.async {
                controlPanel.close()
                deviceWindow.close()
                updateStatusBar()
            }
        }
    }
    
    func closePreview() {
        if SCContext.isCameraRunning() {
            //SCContext.previewType = nil
            if deviceWindow.isVisible { deviceWindow.close() }
            if let preview = SCContext.previewSession { preview.stopRunning() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let content = UNMutableNotificationContent()
        content.title = "Recording Completed".local
        content.body = String(format: "File saved to: %@".local, outputFileURL.path)
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "quickrecorder.completed.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Notification failed to send：\(error.localizedDescription)") }
        }
    }
}
final class WebcamRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    static let shared = WebcamRecorder()

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

    @Published private(set) var state: State = .idle
    @Published private(set) var isBusy = false
    @Published private(set) var isPaused = false
    @Published private(set) var recordedDuration: TimeInterval = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var previewSession: AVCaptureSession?
    @Published private(set) var actualFormatDescription = ""
    @Published private(set) var countdownRemaining = 0

    private struct RecordingSettings {
        let countdown: Int
        let encoder: String
        let preventSleep: Bool
        let showPreview: Bool
        let trimAfterRecord: Bool
        let autoStopMinutes: Int
    }

    private struct FinishResult {
        let url: URL
        let success: Bool
        let duration: TimeInterval
        let settings: RecordingSettings
        let errorMessage: String?
    }

    private let queue = DispatchQueue(label: "QuickRecorder.WebcamRecorder")
    private var backendState: State = .idle
    private var generation = UUID()
    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var recordingURL: URL?
    private var recordingSettings: RecordingSettings?
    private var observers = [NSObjectProtocol]()
    private var countdownTimer: DispatchSourceTimer?
    private var durationTimer: DispatchSourceTimer?
    private var countdownRemainingValue = 0
    private var elapsedBeforeSegment: TimeInterval = 0
    private var stopRequested = false
    private var runtimeFailureMessage: String?
    private var sleepAssertionHeld = false

    private override init() {
        super.init()
    }

    func startPreview(cameraID: String, microphoneID: String? = nil) {
        let reservePreparation: () -> Bool = {
            guard SCContext.streamType == nil && !WebcamScreenRecorder.shared.isBusy else {
                self.errorMessage = "Another recording is already active.".local
                return false
            }
            guard self.state == .idle || self.state == .preparing || self.state == .previewing else { return false }
            if self.state == .idle {
                self.isBusy = true
                self.isPaused = false
                self.state = .preparing
            }
            return true
        }
        let reserved = Thread.isMainThread
            ? reservePreparation()
            : DispatchQueue.main.sync(execute: reservePreparation)
        guard reserved else { return }
        queue.async {
            guard self.backendState == .idle ||
                    self.backendState == .preparing ||
                    self.backendState == .previewing else { return }

            self.generation = UUID()
            let token = self.generation
            self.cancelCountdown()
            self.stopDurationTimer()
            self.tearDownCaptureSession()
            self.backendState = .preparing
            self.publishState(.preparing)
            self.publishError(nil)
            self.publishCountdown(0)
            self.publishFormat("")

            guard !cameraID.isEmpty else {
                self.failPreparation("No camera is selected.".local, token: token)
                return
            }

            let selectedMicrophone = microphoneID.flatMap { $0.isEmpty ? nil : $0 }
            self.authorizeCamera(cameraID: cameraID, microphoneID: selectedMicrophone, token: token)
        }
    }

    func startRecording(autoStopMinutes: Int = 0) {
        queue.async {
            guard self.backendState == .previewing else { return }
            guard let session = self.captureSession,
                  session.isRunning,
                  let output = self.movieOutput else {
                self.publishError("Unable to start camera recording.".local)
                self.cancelSetup()
                return
            }

            let settings = RecordingSettings(
                countdown: max(0, UserDefaults.standard.integer(forKey: "countdown")),
                encoder: UserDefaults.standard.string(forKey: "encoder") ?? Encoder.h264.rawValue,
                preventSleep: UserDefaults.standard.bool(forKey: "preventSleep"),
                showPreview: UserDefaults.standard.bool(forKey: "showPreview"),
                trimAfterRecord: UserDefaults.standard.bool(forKey: "trimAfterRecord"),
                autoStopMinutes: max(0, autoStopMinutes)
            )
            guard let url = self.validatedOutputURL() else {
                self.cancelSetup()
                return
            }
            guard let videoConnection = output.connection(with: .video) else {
                self.publishError("Could not open a video connection.".local)
                self.cancelSetup()
                return
            }

            var encoderList: CFArray?
            let encoderStatus = VTCopyVideoEncoderList(nil, &encoderList)
            let codecTypes = (encoderList as? [[String: Any]])?.compactMap {
                ($0[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value
            } ?? []
            let availableCodecs: [AVVideoCodecType] = [
                (kCMVideoCodecType_H264, AVVideoCodecType.h264),
                (kCMVideoCodecType_HEVC, AVVideoCodecType.hevc)
            ].compactMap { codecTypes.contains($0.0) ? $0.1 : nil }
            guard encoderStatus == noErr, !availableCodecs.isEmpty else {
                self.publishError("No video codecs are available for this camera.".local)
                self.cancelSetup()
                return
            }
            let requestedCodec: AVVideoCodecType = settings.encoder == Encoder.h265.rawValue ? .hevc : .h264
            let codec = availableCodecs.contains(requestedCodec)
                ? requestedCodec
                : (availableCodecs.contains(.h264) ? .h264 : availableCodecs[0])
            output.setOutputSettings([AVVideoCodecKey: codec], for: videoConnection)
            videoConnection.automaticallyAdjustsVideoMirroring = false
            if videoConnection.isVideoMirroringSupported {
                videoConnection.isVideoMirrored = false
            }

            self.recordingSettings = settings
            self.recordingURL = url
            self.stopRequested = false
            self.runtimeFailureMessage = nil
            self.elapsedBeforeSegment = 0
            self.publishDuration(0)
            self.publishError(nil)

            if settings.countdown > 0 {
                self.backendState = .countdown
                self.publishState(.countdown)
                self.publishCountdown(settings.countdown)
                self.startCountdown(settings.countdown)
            } else {
                self.beginFileRecording(output: output, session: session, url: url)
            }
        }
    }

    func stopRecording() {
        queue.async {
            switch self.backendState {
            case .idle:
                break
            case .preparing, .previewing, .countdown:
                self.cancelSetup()
            case .starting:
                self.stopRequested = true
                self.backendState = .finishing
                self.publishState(.finishing)
                if self.movieOutput?.isRecording == true {
                    self.movieOutput?.stopRecording()
                }
            case .recording, .paused:
                self.requestFileStop()
            case .finishing:
                break
            }
        }
    }

    func pauseRecording() {
        queue.async {
            guard let output = self.movieOutput else { return }
            switch self.backendState {
            case .recording:
                output.pauseRecording()
                self.elapsedBeforeSegment = self.currentElapsedDuration()
                self.backendState = .paused
                self.publishDuration(self.elapsedBeforeSegment)
                self.publishState(.paused)
                self.publishPauseState(true, duration: self.elapsedBeforeSegment)
            case .paused:
                output.resumeRecording()
                self.backendState = .recording
                self.publishState(.recording)
                self.publishPauseState(false, duration: self.elapsedBeforeSegment)
            default:
                break
            }
        }
    }

    func cancelPreview() {
        queue.async {
            switch self.backendState {
            case .preparing, .previewing, .countdown:
                self.cancelSetup()
            case .idle, .starting, .recording, .paused, .finishing:
                break
            }
        }
    }

    private func authorizeCamera(cameraID: String, microphoneID: String?, token: UUID) {
        guard generation == token else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizeMicrophone(cameraID: cameraID, microphoneID: microphoneID, token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.queue.async {
                    guard self.generation == token else { return }
                    if granted {
                        self.authorizeMicrophone(cameraID: cameraID, microphoneID: microphoneID, token: token)
                    } else {
                        self.failPreparation("Camera permission is required.".local, token: token)
                    }
                }
            }
        case .denied:
            failPreparation("Camera access is denied. Allow camera access in System Settings.".local, token: token)
        case .restricted:
            failPreparation("Camera access is restricted.".local, token: token)
        @unknown default:
            failPreparation("Camera permission is required.".local, token: token)
        }
    }

    private func authorizeMicrophone(cameraID: String, microphoneID: String?, token: UUID) {
        guard generation == token else { return }
        guard microphoneID != nil else {
            configurePreview(cameraID: cameraID, microphoneID: nil, token: token)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            configurePreview(cameraID: cameraID, microphoneID: microphoneID, token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                self.queue.async {
                    guard self.generation == token else { return }
                    if granted {
                        self.configurePreview(cameraID: cameraID, microphoneID: microphoneID, token: token)
                    } else {
                        self.failPreparation("Microphone permission is required for the selected microphone.".local, token: token)
                    }
                }
            }
        case .denied:
            failPreparation("Microphone access is denied. Allow microphone access in System Settings.".local, token: token)
        case .restricted:
            failPreparation("Microphone access is restricted.".local, token: token)
        @unknown default:
            failPreparation("Microphone permission is required for the selected microphone.".local, token: token)
        }
    }

    private func configurePreview(cameraID: String, microphoneID: String?, token: UUID) {
        guard generation == token else { return }
        guard let camera = SCContext.getCameras().first(where: { $0.uniqueID == cameraID }) else {
            failPreparation("Selected camera is unavailable.".local, token: token)
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(cameraInput) else {
                session.commitConfiguration()
                failPreparation("Unable to add the camera input.".local, token: token)
                return
            }
            session.addInput(cameraInput)

            if let microphoneID {
                guard let microphone = SCContext.getMicrophone().first(where: { $0.uniqueID == microphoneID }) else {
                    session.commitConfiguration()
                    failPreparation("Selected microphone is unavailable.".local, token: token)
                    return
                }
                let microphoneInput: AVCaptureDeviceInput
                do {
                    microphoneInput = try AVCaptureDeviceInput(device: microphone)
                } catch {
                    session.commitConfiguration()
                    failPreparation(String(format: "Unable to create the microphone input: %@".local, error.localizedDescription), token: token)
                    return
                }
                guard session.canAddInput(microphoneInput) else {
                    session.commitConfiguration()
                    failPreparation("Unable to add the microphone input.".local, token: token)
                    return
                }
                session.addInput(microphoneInput)
            }

            let output = AVCaptureMovieFileOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                failPreparation("Unable to add the movie output.".local, token: token)
                return
            }
            session.addOutput(output)
            session.commitConfiguration()

            captureSession = session
            movieOutput = output
            addSessionObservers(session: session, camera: camera, token: token)
            session.startRunning()
            guard session.isRunning else {
                failPreparation("Unable to start camera preview.".local, token: token)
                return
            }
            guard configureSDR(for: camera) else {
                failPreparation("This camera cannot be configured for SDR recording.".local, token: token)
                return
            }

            let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
            let frameRates = camera.activeFormat.videoSupportedFrameRateRanges
            let minimumFrameRate = frameRates.map(\.minFrameRate).min() ?? 0
            let maximumFrameRate = frameRates.map(\.maxFrameRate).max() ?? 0
            let description = String(
                format: "Active camera format: %d × %d, %.0f–%.0f fps range".local,
                Int(dimensions.width),
                Int(dimensions.height),
                minimumFrameRate,
                maximumFrameRate
            )
            backendState = .previewing
            publishPreviewSession(session)
            publishFormat(description)
            publishState(.previewing)
        } catch {
            session.commitConfiguration()
            failPreparation(String(format: "Unable to create the camera input: %@".local, error.localizedDescription), token: token)
        }
    }
    private func configureSDR(for device: AVCaptureDevice) -> Bool {
        do {
            try device.lockForConfiguration()
        } catch {
            return false
        }
        defer { device.unlockForConfiguration() }

        let supportedColorSpaces = device.activeFormat.supportedColorSpaces
        if supportedColorSpaces.contains(.sRGB) {
            device.activeColorSpace = .sRGB
            return true
        }
        if supportedColorSpaces.contains(.P3_D65) {
            device.activeColorSpace = .P3_D65
            return true
        }
        return true
    }


    private func addSessionObservers(session: AVCaptureSession, camera: AVCaptureDevice, token: UUID) {
        let sessionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.queue.async {
                guard let self, self.generation == token else { return }
                let message = error.map { String(format: "Camera capture failed: %@".local, $0.localizedDescription) }
                    ?? "Camera capture failed.".local
                self.handleCaptureFailure(message)
            }
        }
        let deviceObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: camera,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                guard let self, self.generation == token else { return }
                self.handleCaptureFailure("The camera was disconnected.".local)
            }
        }
        observers = [sessionObserver, deviceObserver]
    }

    private func startCountdown(_ seconds: Int) {
        cancelCountdown()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        countdownTimer = timer
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.backendState == .countdown else { return }
            let remaining = max(0, self.countdownRemainingValue - 1)
            self.publishCountdown(remaining)
            if remaining == 0 {
                self.cancelCountdown()
                guard let session = self.captureSession, let output = self.movieOutput, let url = self.recordingURL else {
                    self.handleCaptureFailure("Unable to start recording.".local)
                    return
                }
                self.beginFileRecording(output: output, session: session, url: url)
            }
        }
        timer.resume()
    }


    private func publishCountdown(_ value: Int) {
        countdownRemainingValue = value
        DispatchQueue.main.async { [weak self] in
            self?.countdownRemaining = value
        }
    }


    private func beginFileRecording(output: AVCaptureMovieFileOutput, session: AVCaptureSession, url: URL) {
        guard backendState == .previewing || backendState == .countdown else { return }
        guard session.isRunning, let settings = recordingSettings else {
            handleCaptureFailure("Unable to start recording.".local)
            return
        }

        let mayClaimRecording = DispatchQueue.main.sync { SCContext.streamType == nil }
        guard mayClaimRecording else {
            publishError("Another recording is already active.".local)
            cancelSetup()
            return
        }

        backendState = .starting
        publishState(.starting)
        publishCountdown(0)
        DispatchQueue.main.sync {
            SCContext.filePath = url.path
            SCContext.streamType = .camera
            SCContext.autoStop = settings.autoStopMinutes
            SCContext.isPaused = false
            SCContext.timePassed = 0
            SCContext.startTime = nil
            PopoverState.shared.isPaused = false
            updateStatusBar()
        }
        output.startRecording(to: url, recordingDelegate: self)
    }

    private func requestFileStop() {
        guard backendState == .recording || backendState == .paused else { return }
        stopDurationTimer()
        backendState = .finishing
        publishState(.finishing)
        movieOutput?.stopRecording()
    }

    private func currentElapsedDuration() -> TimeInterval {
        let duration = movieOutput?.recordedDuration.seconds ?? 0
        return duration.isFinite ? max(0, duration) : elapsedBeforeSegment
    }

    private func startDurationTimer() {
        stopDurationTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        durationTimer = timer
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self,
                  self.backendState == .recording || self.backendState == .paused else { return }
            let duration = self.currentElapsedDuration()
            self.publishDuration(duration)
            DispatchQueue.main.async {
                SCContext.timePassed = duration
            }
        }
        timer.resume()
    }

    private func handleCaptureFailure(_ message: String) {
        publishError(message)
        switch backendState {
        case .preparing, .previewing, .countdown:
            cancelSetup()
            publishError(message)
        case .starting:
            runtimeFailureMessage = message
            stopRequested = true
            stopDurationTimer()
            backendState = .finishing
            publishState(.finishing)
            if movieOutput?.isRecording == true {
                movieOutput?.stopRecording()
            }
        case .recording, .paused:
            runtimeFailureMessage = message
            stopRequested = true
            requestFileStop()
        case .finishing:
            runtimeFailureMessage = message
        case .idle:
            break
        }
    }

    private func validatedOutputURL() -> URL? {
        guard UserDefaults.standard.string(forKey: "saveDirectory") != nil else {
            publishError("Select a writable folder before recording.".local)
            return nil
        }

        let baseURL = URL(fileURLWithPath: SCContext.getFilePath())
        let directory = baseURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: directory.path) else {
            publishError("Recording folder does not exist or is not writable.".local)
            return nil
        }

        let basePath = baseURL.path
        var candidate = URL(fileURLWithPath: basePath).appendingPathExtension("mov")
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: "\(basePath) (\(suffix)).mov")
            suffix += 1
        }
        return candidate
    }

    private func cancelSetup() {
        generation = UUID()
        cancelCountdown()
        stopDurationTimer()
        tearDownCaptureSession()
        recordingSettings = nil
        recordingURL = nil
        stopRequested = false
        backendState = .idle
        publishCountdown(0)
        publishState(.idle)
    }

    private func failPreparation(_ message: String, token: UUID) {
        guard generation == token else { return }
        generation = UUID()
        tearDownCaptureSession()
        backendState = .idle
        publishError(message)
        publishState(.idle)
    }

    private func tearDownCaptureSession() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
        captureSession = nil
        movieOutput = nil
        publishPreviewSession(nil)
        publishFormat("")
    }

    private func cancelCountdown() {
        countdownTimer?.setEventHandler {}
        countdownTimer?.cancel()
        countdownTimer = nil
    }

    private func stopDurationTimer() {
        durationTimer?.setEventHandler {}
        durationTimer?.cancel()
        durationTimer = nil
    }

    private func publishState(_ value: State) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = value
            self.isBusy = value != .idle
            self.isPaused = value == .paused
        }
    }

    private func publishError(_ value: String?) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = value }
    }

    private func publishPreviewSession(_ value: AVCaptureSession?) {
        DispatchQueue.main.async { [weak self] in self?.previewSession = value }
    }

    private func publishFormat(_ value: String) {
        DispatchQueue.main.async { [weak self] in self?.actualFormatDescription = value }
    }

    private func publishDuration(_ value: TimeInterval) {
        DispatchQueue.main.async { [weak self] in self?.recordedDuration = max(0, value) }
    }

    private func publishPauseState(_ paused: Bool, duration: TimeInterval) {
        DispatchQueue.main.async {
            SCContext.isPaused = paused
            SCContext.timePassed = duration
            SCContext.startTime = paused ? nil : Date.now.addingTimeInterval(-duration)
            PopoverState.shared.isPaused = paused
        }
    }

    private func completeRecording(_ result: FinishResult, thumbnail: NSImage?) {
        recordingSettings = nil
        recordingURL = nil
        stopRequested = false
        runtimeFailureMessage = nil
        elapsedBeforeSegment = 0
        backendState = .idle
        if sleepAssertionHeld {
            SleepPreventer.shared.allowSleep()
            sleepAssertionHeld = false
        }

        DispatchQueue.main.sync {
            SCContext.streamType = nil
            SCContext.startTime = nil
            SCContext.isPaused = false
            SCContext.autoStop = 0
            SCContext.timePassed = result.duration
            PopoverState.shared.isPaused = false

            if result.success {
                errorMessage = result.errorMessage
                if result.settings.showPreview, let thumbnail {
                    if UserDefaults.standard.bool(forKey: "showPreview") {
                        SCContext.showPreview(path: result.url.path, image: thumbnail)
                    } else {
                        showWebcamPreview(path: result.url.path, image: thumbnail)
                    }
                } else {
                    SCContext.showNotification(
                        title: "Recording Completed".local,
                        body: String(format: "File saved to: %@".local, result.url.path),
                        id: "quickrecorder.webcam.completed.\(UUID().uuidString)"
                    )
                }
                if result.settings.trimAfterRecord {
                    AppDelegate.shared.createNewWindow(
                        view: VideoTrimmerView(videoURL: result.url),
                        title: result.url.lastPathComponent,
                        only: false
                    )
                }
                if let message = result.errorMessage {
                    SCContext.showNotification(
                        title: "Recording stopped unexpectedly".local,
                        body: message,
                        id: "quickrecorder.webcam.interrupted.\(UUID().uuidString)"
                    )
                }
            } else {
                let message = result.errorMessage ?? "Recording did not produce a playable MOV file.".local
                errorMessage = message
                SCContext.showNotification(
                    title: "Failed to save file".local,
                    body: message,
                    id: "quickrecorder.webcam.error.\(UUID().uuidString)"
                )
            }
            updateStatusBar()
            previewSession = nil
            actualFormatDescription = ""
            countdownRemaining = 0
            recordedDuration = result.duration
            isPaused = false
            isBusy = false
            state = .idle
        }
    }

    private func showWebcamPreview(path: String, image: NSImage) {
        guard let screen = SCContext.getScreenWithMouse() else {
            SCContext.showNotification(
                title: "Recording Completed".local,
                body: String(format: "File saved to: %@".local, path),
                id: "quickrecorder.webcam.completed.\(UUID().uuidString)"
            )
            return
        }
        previewWindow.contentView = NSHostingView(rootView: PreviewView(frame: image, filePath: path))
        previewWindow.setFrameOrigin(NSPoint(x: screen.frame.maxX - 280, y: screen.frame.minY + 20))
        previewWindow.orderFront(nil)
    }

    private func makeThumbnail(for url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    private func finishRecording(output: AVCaptureFileOutput, url: URL, error: Error?) {
        queue.async {
            guard self.movieOutput === output,
                  self.backendState == .finishing ||
                    self.backendState == .starting ||
                    self.backendState == .recording ||
                    self.backendState == .paused,
                  let settings = self.recordingSettings else { return }

            self.backendState = .finishing
            self.publishState(.finishing)
            self.stopDurationTimer()
            let nsError = error as NSError?
            let wasSuccessfullyFinished = nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            let outputDuration = self.movieOutput?.recordedDuration.seconds ?? 0
            let hasMedia = FileManager.default.fileExists(atPath: url.path) && fileSize > 0
                && outputDuration.isFinite && outputDuration > 0
            let success = (error == nil || wasSuccessfullyFinished) && hasMedia
            let duration = outputDuration.isFinite && outputDuration > 0
                ? outputDuration
                : self.currentElapsedDuration()
            let errorMessage: String?
            if success {
                errorMessage = self.runtimeFailureMessage
            } else if let runtimeFailureMessage = self.runtimeFailureMessage {
                errorMessage = runtimeFailureMessage
            } else if let error {
                errorMessage = String(format: "Recording failed: %@".local, error.localizedDescription)
            } else {
                errorMessage = "Recording did not produce a playable MOV file.".local
            }
            let result = FinishResult(
                url: url,
                success: success,
                duration: duration,
                settings: settings,
                errorMessage: errorMessage
            )
            self.tearDownCaptureSession()
            self.generation = UUID()

            if success && settings.showPreview {
                DispatchQueue.global(qos: .utility).async {
                    let thumbnail = self.makeThumbnail(for: url)
                    self.queue.async { self.completeRecording(result, thumbnail: thumbnail) }
                }
            } else {
                self.completeRecording(result, thumbnail: nil)
            }
        }
    }


    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async {
            guard self.movieOutput === output,
                  self.backendState == .starting || self.backendState == .finishing else { return }
            if self.backendState == .finishing || self.stopRequested {
                output.stopRecording()
                return
            }

            self.backendState = .recording
            self.elapsedBeforeSegment = 0
            self.publishState(.recording)
            self.startDurationTimer()
            if self.recordingSettings?.preventSleep == true {
                SleepPreventer.shared.preventSleep(reason: "Webcam recording in progress")
                self.sleepAssertionHeld = true
            }
            DispatchQueue.main.sync {
                SCContext.startTime = Date.now
                SCContext.isPaused = false
                PopoverState.shared.isPaused = false
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        finishRecording(output: output, url: outputFileURL, error: error)
    }
}
