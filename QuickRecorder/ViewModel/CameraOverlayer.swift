//
//  CameraOverlayer.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/29.
//

import SwiftUI
import AppKit
import Foundation
import AVFoundation
import ScreenCaptureKit

extension AppDelegate {
    func startCameraOverlayer(size: NSSize = NSSize(width: 200, height: 200)){
        guard let screen = SCContext.getScreenWithMouse() else { return }
        camWindow.contentView = NSHostingView(rootView: SwiftCameraView(type: .camera))
        let frame = NSRect(x: (screen.visibleFrame.width-size.width)/2+screen.frame.minX, y: (screen.visibleFrame.height-size.height)/2+screen.frame.minY, width: size.width, height: size.height)
        camWindow.setFrame(frame, display: true)
        //camWindow.setFrameOrigin(NSPoint(x: screen.visibleFrame.width/2-100, y: screen.visibleFrame.height/2-100))
        camWindow.contentView?.wantsLayer = true
        camWindow.contentView?.layer?.cornerRadius = 5
        camWindow.contentView?.layer?.masksToBounds = true
        camWindow.orderFront(self)
    }
}

struct CameraView: NSViewRepresentable {
    var type: StreamType!
    func makeNSView(context: Context) -> CameraNSView {
        let cameraView = CameraNSView(frame: .zero, type: type)
        return cameraView
    }

    func updateNSView(_ nsView: CameraNSView, context: Context) {
        // Update the view
    }
}

class CameraNSView: NSView {
    let type: StreamType
    var session = SCContext.captureSession
    var previewLayer: AVCaptureVideoPreviewLayer? = nil
    
    init(frame frameRect: NSRect, type: StreamType) {
        self.type = type
        super.init(frame: frameRect)
        wantsLayer = true
        setupCaptureSession()
    }
        
    required init?(coder decoder: NSCoder) {
        // 如果您的类型不是一个可选类型，您可以将其设置为一个默认值
        self.type = .camera
        super.init(coder: decoder)
        wantsLayer = true
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        if type == .idevice { session = SCContext.previewSession }
        guard let session = session else { return }
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer!.frame = bounds
        if type == .idevice {
            previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspect
        }
        if type == .camera {
            previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
            previewLayer!.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        }
        layer?.addSublayer(previewLayer!)
    }
    
    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

struct SwiftCameraView: View {
    var type: StreamType!
    @State private var hover = false
    @State private var isFlipped = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if type == .idevice {
                    Color.black
                    Text("Please unlock!")
                        .foregroundStyle(.white)
                }
                ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                    CameraView(type: type)
                        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    Button(action: {
                        if type == .idevice {
                            for w in NSApp.windows.filter({ $0.title == "iDevice Overlayer".local }) { w.close() }
                        } else {
                            isFlipped.toggle()
                        }
                    }, label: {
                        ZStack {
                            Circle().frame(width: 30)
                                .foregroundStyle(hover ? .blue : .gray)
                            if type == .idevice {
                                Image(systemName: "xmark")
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                    .foregroundStyle(.white)
                                    .offset(y: -1)
                            }
                        }
                        .opacity(hover ? 0.8 : 0.2)
                        .onHover{ hovering in hover = hovering }
                    }).buttonStyle(.plain).padding(10)
                }.frame(width: geometry.size.width, height: geometry.size.height)
                if SCContext.streamType == .window {
                    Text("Unable to use camera overlayer when recording a single window!".local
                         + (isMacOS14 ? " Please use \"Presenter Overlay\"".local : "")
                    )
                    .padding()
                    .colorInvert()
                    .background(.secondary)
                }
            }
        }
        .frame(minWidth: 100, minHeight: 100)
        .onHover { hovering in
            hideMousePointer = hovering
            hideScreenMagnifier = hovering
        }
    }
}


struct CameraPopoverView: View {
    var closePopover: () -> Void
    @State private var cameras = SCContext.getCameras()
    @State private var devices = SCContext.getiDevice()
    @State private var hoverIndex = -1
    @State private var hoverIndex2 = -1
    @State private var disabled = false
    //@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var appDelegate = AppDelegate.shared
    
    var body: some View {
        VStack( alignment: .leading, spacing: 0) {
            if cameras.count < 1 {
                HStack {
                    ZStack {
                        Circle().frame(width: 26)
                            .foregroundStyle(.primary)
                            .opacity(0.2)
                        Image(systemName:"video.slash.fill")
                            .foregroundStyle(.primary)
                            .font(.system(size: 12))
                    }.padding(.leading, 9)
                    Text("No Cameras Found!".local)
                        .padding(.vertical, 8).padding(.trailing, 10)
                }.frame(maxWidth: .infinity)
            }
            ForEach(cameras.indices, id: \.self) { index in
                Button(action: {
                    closePopover()
                    if SCContext.recordCam == cameras[index].localizedName {
                        SCContext.recordCam = ""
                        appDelegate.closeCamera()
                        return
                    }
                    SCContext.recordCam = cameras[index].localizedName
                    appDelegate.closeCamera()
                    appDelegate.recordingCamera(with: cameras[index])
                }, label: {
                    HStack {
                        ZStack {
                            Circle().frame(width: 26)
                                .foregroundStyle(SCContext.recordCam == cameras[index].localizedName ? .blue : .primary)
                                .opacity(SCContext.recordCam == cameras[index].localizedName ? 1.0 : 0.2)
                            Image(systemName: "video.fill")
                                .foregroundStyle(SCContext.recordCam == cameras[index].localizedName ? .white : .primary)
                                .font(.system(size: 12))
                        }.padding(.leading, 9)
                        Text(cameras[index].localizedName)
                            .padding(.vertical, 8).padding(.trailing, 10)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .foregroundStyle(.primary)
                            .opacity(hoverIndex == index ? 0.2 : 0.0)
                    )
                    .onHover{ hovering in
                        if hoverIndex != index { hoverIndex = index }
                        if !hovering { hoverIndex = -1 }
                    }
                }).buttonStyle(.plain)
            }
            if SCContext.streamType != .window {
                if !devices.isEmpty { Divider().padding(.vertical, 4) }
                ForEach(devices.indices, id: \.self) { index in
                    Button(action: {
                        closePopover()
                        if SCContext.recordDevice == devices[index].localizedName {
                            SCContext.recordDevice = ""
                            AVOutputClass.shared.closePreview()
                            return
                        }
                        SCContext.recordDevice = devices[index].localizedName
                        AVOutputClass.shared.closePreview()
                        DispatchQueue.global().async {
                            AVOutputClass.shared.startRecording(with: devices[index], mute: true, didOutput: false)
                        }
                    }, label: {
                        HStack {
                            ZStack {
                                Circle().frame(width: 26)
                                    .foregroundStyle(SCContext.recordDevice == devices[index].localizedName ? .blue : .primary)
                                    .opacity(SCContext.recordDevice == devices[index].localizedName ? 1.0 : 0.2)
                                Image(systemName:"apple.logo")
                                    .foregroundStyle(SCContext.recordDevice == devices[index].localizedName ? .white : .primary)
                                    .font(.system(size: 12))
                            }.padding(.leading, 9)
                            Text(devices[index].localizedName)
                                .padding(.vertical, 8).padding(.trailing, 10)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .foregroundStyle(.primary)
                                .opacity(hoverIndex2 == index ? 0.2 : 0.0)
                        )
                        .onHover{ hovering in
                            if hoverIndex2 != index { hoverIndex2 = index }
                            if !hovering { hoverIndex2 = -1 }
                        }
                    }).buttonStyle(.plain)
                }
            }
        }.padding(5)
    }
}

struct WebcamRecordingView: View {
    @StateObject private var recorder = WebcamRecorder.shared
    @State private var cameras = SCContext.getCameras()
    @State private var microphones = SCContext.getMicrophone()
    @State private var selectedCameraID = SCContext.getCameras().first?.uniqueID ?? ""
    @State private var selectedMicrophoneID = ""
    @State private var previewIsMirrored = true
    @State private var autoStopMinutes = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Webcam-only recording".local)
                    .font(.headline)

                if cameras.isEmpty {
                    Text("No cameras were found.".local)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Camera".local, selection: $selectedCameraID) {
                        ForEach(cameras, id: \.uniqueID) { camera in
                            Text(camera.localizedName).tag(camera.uniqueID)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!canChangeSources)

                    Picker("Microphone".local, selection: $selectedMicrophoneID) {
                        Text("No microphone".local).tag("")
                        ForEach(microphones, id: \.uniqueID) { microphone in
                            Text(microphone.localizedName).tag(microphone.uniqueID)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!canChangeSources)
                }

                if let session = recorder.previewSession {
                    WebcamPreviewView(session: session, mirrored: previewIsMirrored)
                        .frame(height: 230)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(Color.black)
                        if recorder.state == .preparing {
                            ProgressView("Preparing camera…".local)
                                .foregroundColor(.white)
                        } else if cameras.isEmpty {
                            Text("No cameras were found.".local)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(height: 230)
                }

                if !recorder.actualFormatDescription.isEmpty {
                    Text(recorder.actualFormatDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle("Mirror preview".local, isOn: $previewIsMirrored)
                    .toggleStyle(.checkbox)
                    .disabled(recorder.previewSession == nil)
                Text("Preview mirroring does not affect the saved video.".local)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Webcam recordings use MOV and SDR.".local)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Microphone mute and echo cancellation are unavailable for webcam-only recording.".local)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let message = recorder.errorMessage {
                    Text(message)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                controls
            }
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 430)
        .background(WindowAccessor(onWindowClose: {
            recorder.cancelPreview()
        }))
        .onAppear {
            if recorder.state == .idle {
                recorder.startPreview(cameraID: selectedCameraID, microphoneID: selectedMicrophoneID)
            }
        }
        .onDisappear {
            recorder.cancelPreview()
        }
        .onChange(of: selectedCameraID) { _ in
            restartPreviewForSourceChange()
        }
        .onChange(of: selectedMicrophoneID) { _ in
            restartPreviewForSourceChange()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .idle:
            HStack {
                Button("Start preview".local) {
                    recorder.startPreview(cameraID: selectedCameraID, microphoneID: selectedMicrophoneID)
                }
                .disabled(selectedCameraID.isEmpty)
                Button("Refresh devices".local) { refreshDevices() }
                Spacer()
                Button("Cancel".local) { cancelSetupView() }
            }
        case .preparing:
            HStack {
                ProgressView()
                Text("Preparing camera…".local)
                Spacer()
                Button("Cancel".local) { cancelSetupView() }
            }
        case .previewing:
            Stepper(value: $autoStopMinutes, in: 0...180) {
                Text(autoStopMinutes == 0
                     ? "Auto-stop is off".local
                     : String(format: "Stop after %d minutes".local, autoStopMinutes))
            }
            HStack {
                Button("Start recording".local) {
                    recorder.startRecording(autoStopMinutes: autoStopMinutes)
                }
                Spacer()
                Button("Cancel".local) { cancelSetupView() }
            }
        case .countdown:
            HStack {
                Text(String(format: "Recording starts in %d seconds".local, recorder.countdownRemaining))
                    .monospacedDigit()
                Spacer()
                Button("Cancel countdown".local) { recorder.stopRecording() }
            }
        case .starting:
            HStack {
                ProgressView()
                Text("Starting recording…".local)
                Spacer()
                Button("Stop recording".local) { recorder.stopRecording() }
            }
        case .recording, .paused:
            HStack {
                Text(formattedDuration)
                    .monospacedDigit()
                Spacer()
                Button(recorder.isPaused ? "Resume recording".local : "Pause recording".local) {
                    recorder.pauseRecording()
                }
                Button("Stop recording".local) { recorder.stopRecording() }
            }
        case .finishing:
            HStack {
                ProgressView()
                Text("Saving recording…".local)
            }
        }
    }

    private var canChangeSources: Bool {
        recorder.state == .idle || recorder.state == .preparing || recorder.state == .previewing
    }

    private var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter.string(from: recorder.recordedDuration) ?? "00:00"
    }

    private func refreshDevices() {
        cameras = SCContext.getCameras()
        microphones = SCContext.getMicrophone()
        if !cameras.contains(where: { $0.uniqueID == selectedCameraID }) {
            selectedCameraID = cameras.first?.uniqueID ?? ""
        }
        if !microphones.contains(where: { $0.uniqueID == selectedMicrophoneID }) {
            selectedMicrophoneID = ""
        }
    }

    private func restartPreviewForSourceChange() {
        guard canChangeSources else { return }
        recorder.startPreview(cameraID: selectedCameraID, microphoneID: selectedMicrophoneID)
    }
    private func cancelSetupView() {
        recorder.cancelPreview()
        NSApp.windows.first(where: { $0.title == "Webcam".local })?.close()
    }
}

struct WebcamPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> WebcamPreviewNSView {
        let view = WebcamPreviewNSView(frame: .zero)
        view.configure(session: session, mirrored: mirrored)
        return view
    }

    func updateNSView(_ nsView: WebcamPreviewNSView, context: Context) {
        nsView.configure(session: session, mirrored: mirrored)
    }
}

final class WebcamPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    func configure(session: AVCaptureSession, mirrored: Bool) {
        if previewLayer?.session !== session {
            previewLayer?.removeFromSuperlayer()
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            previewLayer = layer
            self.layer?.addSublayer(layer)
        }
        previewLayer?.frame = bounds
        previewLayer?.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

@available(macOS 13, *)
struct WebcamScreenRecordingView: View {
    @StateObject private var recorder = WebcamScreenRecorder.shared
    @State private var cameras = SCContext.getCameras()
    @State private var microphones = SCContext.getMicrophone()
    @State private var displays = [SCDisplay]()
    @State private var selectedCameraID = SCContext.getCameras().first?.uniqueID ?? ""
    @State private var selectedMicrophoneID = ""
    @State private var selectedDisplayID: CGDirectDisplayID = 0
    @State private var captureSystemAudio = false
    @State private var remuxAudio = true
    @State private var layout = WebcamScreenLayout()
    @State private var autoStopMinutes = 0
    @State private var refreshingSources = false
    @State private var sourceError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Webcam + Screen".local).font(.headline)
                Text("Record one display with a webcam picture-in-picture.".local)
                    .font(.caption).foregroundColor(.secondary)

                sourcePickers
                    .disabled(!canChangeSources || refreshingSources)

                ZStack {
                    Color.black
                    if let image = recorder.previewImage {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else if recorder.state == .preparing || refreshingSources {
                        ProgressView("Preparing screen and camera…".local)
                            .foregroundColor(.white)
                    } else {
                        Text("Start preview to see the composite.".local)
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if !recorder.actualFormatDescription.isEmpty {
                    Text(recorder.actualFormatDescription)
                        .font(.caption).foregroundColor(.secondary)
                }

                layoutControls.disabled(!canChangeSources)

                Text("SDR only. HDR, transparency, microphone mute and echo cancellation are unavailable.".local)
                    .font(.caption).foregroundColor(.secondary)
                Text("QuickRecorder windows are excluded. Presenter Overlay stops this recording.".local)
                    .font(.caption).foregroundColor(.secondary)

                if let message = recorder.errorMessage ?? sourceError {
                    Text(message).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                controls
            }
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 480)
        .background(WindowAccessor(onWindowClose: { recorder.cancelPreview() }))
        .onAppear {
            if recorder.state == .idle { refreshSources() }
        }
        .onDisappear { recorder.cancelPreview() }
        .onChange(of: selectedCameraID) { _ in restartPreview() }
        .onChange(of: selectedMicrophoneID) { _ in restartPreview() }
        .onChange(of: selectedDisplayID) { _ in restartPreview() }
        .onChange(of: captureSystemAudio) { _ in restartPreview() }
        .onChange(of: layout.position) { _ in recorder.updateLayout(layout) }
        .onChange(of: layout.widthFraction) { _ in recorder.updateLayout(layout) }
        .onChange(of: layout.mirrored) { _ in recorder.updateLayout(layout) }
    }

    private var sourcePickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Display".local, selection: $selectedDisplayID) {
                ForEach(displays, id: \.displayID) { display in
                    Text(displayName(display)).tag(display.displayID)
                }
            }.pickerStyle(.menu)
            Picker("Camera".local, selection: $selectedCameraID) {
                ForEach(cameras, id: \.uniqueID) { camera in
                    Text(camera.localizedName).tag(camera.uniqueID)
                }
            }.pickerStyle(.menu)
            if cameras.isEmpty {
                Text("No cameras were found.".local).foregroundColor(.secondary)
            }
            Picker("Microphone".local, selection: $selectedMicrophoneID) {
                Text("No microphone".local).tag("")
                ForEach(microphones, id: \.uniqueID) { microphone in
                    Text(microphone.localizedName).tag(microphone.uniqueID)
                }
            }.pickerStyle(.menu)
            Toggle("Record System Audio".local, isOn: $captureSystemAudio)
                .toggleStyle(.checkbox)
            if captureSystemAudio && !selectedMicrophoneID.isEmpty {
                Toggle("Record Microphone to Main Track".local, isOn: $remuxAudio)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var layoutControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Webcam position".local, selection: $layout.position) {
                Text("Top left".local).tag(WebcamScreenLayout.Position.topLeft)
                Text("Top right".local).tag(WebcamScreenLayout.Position.topRight)
                Text("Bottom left".local).tag(WebcamScreenLayout.Position.bottomLeft)
                Text("Bottom right".local).tag(WebcamScreenLayout.Position.bottomRight)
            }.pickerStyle(.menu)
            HStack {
                Text("Webcam size".local)
                Slider(value: $layout.widthFraction, in: 0.15...0.40, step: 0.01)
                Text("\(Int(layout.widthFraction * 100))%").monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
            Toggle("Mirror webcam in saved video".local, isOn: $layout.mirrored)
                .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .idle:
            HStack {
                Button("Start preview".local) { startPreview() }
                    .disabled(selectedCameraID.isEmpty || selectedDisplayID == 0 || refreshingSources)
                Button("Refresh sources".local) { refreshSources() }
                    .disabled(refreshingSources)
                Spacer()
                Button("Cancel".local) { cancelSetupView() }
            }
        case .preparing:
            HStack {
                ProgressView()
                Text("Preparing screen and camera…".local)
                Spacer()
                Button("Cancel".local) { cancelSetupView() }
            }
        case .previewing:
            Stepper(value: $autoStopMinutes, in: 0...180) {
                Text(autoStopMinutes == 0
                     ? "Auto-stop is off".local
                     : String(format: "Stop after %d minutes".local, autoStopMinutes))
            }
            HStack {
                Button("Start recording".local) {
                    recorder.startRecording(autoStopMinutes: autoStopMinutes, remuxAudio: remuxAudio)
                }
                Spacer()
                Button("Cancel".local) { cancelSetupView() }
            }
        case .countdown:
            HStack {
                Text(String(format: "Recording starts in %d seconds".local, recorder.countdownRemaining))
                    .monospacedDigit()
                Spacer()
                Button("Cancel countdown".local) { recorder.stopRecording() }
            }
        case .starting:
            HStack {
                ProgressView()
                Text("Starting recording…".local)
                Spacer()
                Button("Stop recording".local) { recorder.stopRecording() }
            }
        case .recording, .paused:
            HStack {
                Text(formattedDuration).monospacedDigit()
                Spacer()
                Button(recorder.isPaused ? "Resume recording".local : "Pause recording".local) {
                    recorder.pauseRecording()
                }
                Button("Stop recording".local) { recorder.stopRecording() }
            }
        case .finishing:
            HStack {
                ProgressView()
                Text("Saving recording…".local)
            }
        }
    }

    private var canChangeSources: Bool {
        recorder.state == .idle || recorder.state == .previewing
    }

    private var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter.string(from: recorder.recordedDuration) ?? "00:00"
    }

    private func displayName(_ display: SCDisplay) -> String {
        if let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) {
            return screen.localizedName
        }
        return String(format: "Display %u".local, display.displayID)
    }

    private func startPreview() {
        sourceError = nil
        recorder.updateLayout(layout)
        recorder.startPreview(cameraID: selectedCameraID,
                              microphoneID: selectedMicrophoneID,
                              displayID: selectedDisplayID,
                              captureSystemAudio: captureSystemAudio)
    }

    private func restartPreview() {
        guard recorder.state == .previewing, !refreshingSources else { return }
        startPreview()
    }

    private func refreshSources() {
        guard recorder.state == .idle, !refreshingSources else { return }
        refreshingSources = true
        sourceError = nil
        cameras = SCContext.getCameras()
        microphones = SCContext.getMicrophone()
        if !cameras.contains(where: { $0.uniqueID == selectedCameraID }) {
            selectedCameraID = cameras.first?.uniqueID ?? ""
        }
        if !microphones.contains(where: { $0.uniqueID == selectedMicrophoneID }) {
            selectedMicrophoneID = ""
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            DispatchQueue.main.async {
                refreshingSources = false
                if let content {
                    displays = content.displays
                    if !displays.contains(where: { $0.displayID == selectedDisplayID }) {
                        selectedDisplayID = displays.first?.displayID ?? 0
                    }
                    if displays.isEmpty {
                        sourceError = "No displays were found.".local
                    }
                } else {
                    displays = []
                    selectedDisplayID = 0
                    sourceError = error?.localizedDescription ?? "Unable to load displays.".local
                }
            }
        }
    }

    private func cancelSetupView() {
        recorder.cancelPreview()
        NSApp.windows.first(where: { $0.title == "Webcam + Screen".local })?.close()
    }
}
