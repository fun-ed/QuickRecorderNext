//
//  RecordEngine.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/17.
//

import AppKit
import Combine
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import UserNotifications
import ScreenCaptureKit
import AVFoundation
import AVFAudio
import VideoToolbox
import AECAudioStream

extension AppDelegate {
    @objc func prepRecord(type: String, screens: SCDisplay?, windows: [SCWindow]?, applications: [SCRunningApplication]?, fastStart: Bool = false) {
        guard !SCContext.isRecording else { return }
        switch type {
        case "window":  SCContext.streamType = .window
        case "windows":  SCContext.streamType = .windows
        case "display": SCContext.streamType = .screen
        case "application": SCContext.streamType = .application
        case "area": SCContext.streamType = .screenarea
        case "audio":   SCContext.streamType = .systemaudio
            default: return // if we don't even know what to record I don't think we should even try
        }
        var isDirectory: ObjCBool = false
        let outputPath = saveDirectory!
        if fd.fileExists(atPath: outputPath, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                SCContext.streamType = nil
                _ = createAlert(title: "Failed to Record".local, message: "The output path is a file instead of a folder!".local, button1: "OK").runModal()
                return
            }
        } else {
            do {
                try fd.createDirectory(atPath: outputPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                SCContext.streamType = nil
                _ = createAlert(title: "Failed to Record".local, message: "Unable to create output folder!".local, button1: "OK").runModal()
                return
            }
        }
        
        // file preparation
        if let screens = screens {
            SCContext.screen = SCContext.availableContent!.displays.first(where: { $0 == screens })
        } else { SCContext.streamType = nil; return }
        
        if let windows = windows {
            SCContext.window = SCContext.availableContent!.windows.filter({ windows.contains($0) })
        } else { if SCContext.streamType == .window { SCContext.streamType = nil; return } }
        
        if let applications = applications {
            SCContext.application = SCContext.availableContent!.applications.filter({ applications.contains($0) })
        } else { if SCContext.streamType == .application { SCContext.streamType = nil; return } }
        
        let screen = SCContext.screen ?? SCContext.getSCDisplayWithMouse()!
        let qrSelf = SCContext.getSelf()
        let qrWindows = SCContext.getSelfWindows()
        let dockApp = SCContext.availableContent!.applications.first(where: { $0.bundleIdentifier.description == "com.apple.dock" })
        let wallpaper = SCContext.availableContent!.windows.filter({
            guard let title = $0.title else { return false }
            return $0.owningApplication?.bundleIdentifier == "com.apple.dock" && title != "LPSpringboard" && title != "Dock"
        })
        let desktop = SCContext.availableContent!.windows.filter({
            guard let title = $0.title else { return false }
            return $0.owningApplication?.bundleIdentifier == "" && title == "Desktop"
        })
        let dockWindow = SCContext.availableContent!.windows.filter({
            guard let title = $0.title else { return true }
            return $0.owningApplication?.bundleIdentifier == "com.apple.dock" && title == "Dock"
        })
        let desktopFiles = SCContext.availableContent!.windows.filter({
            $0.owningApplication?.bundleIdentifier == "com.apple.finder"
            && $0.title == "" && $0.frame == screen.frame })
        let controlCenterWindow = SCContext.availableContent!.applications.filter({ $0.bundleIdentifier == "com.apple.controlcenter" })
        let mouseWindow = SCContext.availableContent!.windows.filter({ $0.title == "Mouse Pointer".local && $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier })
        let camLayer = SCContext.availableContent!.windows.filter({ $0.title == "Camera Overlayer".local && $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier })
        var appBlackList = [String]()
        if let savedData = ud.data(forKey: "hiddenApps"),
           let decodedApps = try? JSONDecoder().decode([AppInfo].self, from: savedData) {
            appBlackList = (decodedApps as [AppInfo]).map({ $0.bundleID })
        }
        let excliudedApps = SCContext.availableContent!.applications.filter({ appBlackList.contains($0.bundleIdentifier) })
        
        if SCContext.streamType == .window || SCContext.streamType == .windows {
            if var includ = SCContext.window {
                if includ.count > 1 {
                    if highlightMouse { includ += mouseWindow }
                    if background.rawValue == BackgroundType.wallpaper.rawValue { if dockApp != nil { includ += wallpaper }}
                    SCContext.filter = SCContentFilter(display: screen, including: includ + camLayer)
                    if #available(macOS 14.2, *) { SCContext.filter?.includeMenuBar = includeMenuBar }
                } else {
                    SCContext.streamType = .window
                    SCContext.filter = SCContentFilter(desktopIndependentWindow: includ[0])
                }
            }
        } else {
            if SCContext.streamType == .screen || SCContext.streamType == .screenarea {
                if SCContext.streamType == .screenarea {
                    if let area = SCContext.screenArea, let name = screen.nsScreen?.localizedName {
                        let a = ["x": area.origin.x, "y": area.origin.y, "width": area.width, "height": area.height]
                        ud.set([name: a], forKey: "savedArea")
                    }
                }
                var excluded = [SCRunningApplication]()
                var except = [SCWindow]()
                excluded += excliudedApps
                if hideCCenter { excluded += controlCenterWindow }
                if hideSelf { if let qrWindows = qrWindows { except += qrWindows }}
                if background.rawValue != BackgroundType.wallpaper.rawValue { if dockApp != nil {
                    except += wallpaper
                    except += desktop
                }}
                if hideDesktopFiles { except += desktopFiles }
                SCContext.filter = SCContentFilter(display: screen, excludingApplications: excluded, exceptingWindows: except)
                if #available(macOS 14.2, *) { SCContext.filter?.includeMenuBar = ((SCContext.streamType == .screen || SCContext.streamType == .screenarea) && includeMenuBar) }
            }
            if SCContext.streamType == .application {
                var includ = SCContext.application!
                var except = [SCWindow]()
                if let qrSelf = qrSelf { includ.append(qrSelf) }
                let withFinder = includ.map{ $0.bundleIdentifier }.contains("com.apple.finder")
                if withFinder && hideDesktopFiles { except += desktopFiles }
                if hideSelf { if let qrWindows = qrWindows { except += qrWindows }}
                //if ud.bool(forKey: "highlightMouse") { if let qrSelf = qrSelf { includ.append(qrSelf) }}
                if background.rawValue == BackgroundType.wallpaper.rawValue { if let dock = dockApp { includ.append(dock); except += dockWindow}}
                SCContext.filter = SCContentFilter(display: screen, including: includ, exceptingWindows: except)
                if #available(macOS 14.2, *) { SCContext.filter?.includeMenuBar = includeMenuBar }
            }
        }
        if SCContext.streamType == .systemaudio {
            SCContext.filter = SCContentFilter(display: screen, excludingApplications: [], exceptingWindows: [])
            prepareAudioRecording()
        }
        Task { await record(filter: SCContext.filter!, fastStart: fastStart) }
    }

    func record(filter: SCContentFilter, fastStart: Bool = true) async {
        SCContext.timeOffset = CMTimeMake(value: 0, timescale: 0)
        SCContext.isPaused = false
        SCContext.isResume = false
        DispatchQueue.main.async {
            PopoverState.shared.isMicMuted = SCContext.isMicMuted
        }

        let audioOnly = SCContext.streamType == .systemaudio
        
        let conf: SCStreamConfiguration
#if compiler(>=6.0)
        if recordHDR {
            if #available(macOS 15, *) {
                // TODO change here. https://developer.apple.com/videos/play/wwdc2024/10088/?time=191
                // For canonical display, it means you are capturing HDR content that is optimized for sharing with other HDR devices.
                // hdrLocalDisplay or hdrCanonicalDisplay


                conf = SCStreamConfiguration(preset: .captureHDRStreamLocalDisplay)
            } else { conf = SCStreamConfiguration() }
        } else { conf = SCStreamConfiguration() }
#else
        conf = SCStreamConfiguration()
#endif
        conf.width = 2
        conf.height = 2
        
        if !audioOnly {
            if #available(macOS 14.0, *) {
                conf.width = Int(filter.contentRect.width) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
                conf.height = Int(filter.contentRect.height) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
            } else {
                guard let pointPixelScaleOld = (SCContext.screen ?? SCContext.getSCDisplayWithMouse()!).nsScreen?.backingScaleFactor else { return }
                if SCContext.streamType == .application || SCContext.streamType == .windows || SCContext.streamType == .screen {
                    let frame = (SCContext.screen ?? SCContext.getSCDisplayWithMouse()!).frame
                    conf.width = Int(frame.width)
                    conf.height = Int(frame.height)
                }
                if SCContext.streamType == .window {
                    let frame = SCContext.window![0].frame
                    conf.width = Int(frame.width)
                    conf.height = Int(frame.height)
                }
                if SCContext.streamType == .screenarea {
                    let frame = SCContext.screenArea!
                    conf.width = Int(frame.width)
                    conf.height = Int(frame.height)
                }
                conf.width = conf.width * (highRes == 2 ? Int(pointPixelScaleOld) : 1)
                conf.height = conf.height * (highRes == 2 ? Int(pointPixelScaleOld) : 1)
            }
            
            if fastStart{
                conf.showsCursor = false
            } else{
                conf.showsCursor = showMouse
            }
                    

            if background.rawValue != BackgroundType.wallpaper.rawValue { conf.backgroundColor = SCContext.getBackgroundColor() }
            if !recordHDR {
                conf.pixelFormat = kCVPixelFormatType_32BGRA
                conf.colorSpaceName = CGColorSpace.sRGB
                //if withAlpha { conf.pixelFormat = kCVPixelFormatType_32BGRA }
            } else {
                // For recording HDR in a BT2020 PQ container
                conf.colorSpaceName = CGColorSpace.itur_2100_PQ
//                https://developer.apple.com/videos/play/wwdc2022/10155/ guide on how to record 4k60
//                streamConfiguration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    
// Note: 420 encoding causes color bleed at edges, e.g. youtube settings icon with red logo
                // conf.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
//              dont exceed 8 frames  https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth
//                lower queuedepth has more stutter, dont go below 4 https://github.com/nonstrict-hq/ScreenCaptureKit-Recording-example/blob/main/Sources/sckrecording/main.swift
                conf.queueDepth = 8
            }
        }
        
        if #available(macOS 13, *) {
            conf.capturesAudio = recordWinSound || fastStart || audioOnly
            conf.sampleRate = 48000
            conf.channelCount = 2
        }
        

        //  conf.minimumFrameInterval = CMTime(value: 1, timescale: audioOnly ? CMTimeScale.max : CMTimeScale(frameRate))
         conf.minimumFrameInterval = CMTime(value: 1, timescale: audioOnly ? CMTimeScale.max : (frameRate >= 60 ? 0 : CMTimeScale(frameRate)))

//        CMTimeScale is the denominator in the fraction
//        conf.minimumFrameInterval = CMTime(seconds: audioOnly ? Double(CMTimeScale.max) : Double(1)/Double(frameRate), preferredTimescale: 10000)

        // note: ScreenCaptureKit only delivers frames when something changes
        // https://www.reddit.com/r/swift/comments/158n4c9/comment/ju847rm/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button

        //blog post from the reddit comment https://nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit/

        //https://github.com/nonstrict-hq/ScreenCaptureKit-Recording-example

        // https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval
        //minimumFrameInterval: Use this value to throttle the rate at which you receive updates. The default value is 0, which indicates that the system uses the maximum supported frame rate.

        print("Frame interval passed to ScreenCaptureKit. (timescale is FPS. 0 means no throttling): \(conf.minimumFrameInterval)")
        

        if SCContext.streamType == .screenarea {
            if let nsRect = SCContext.screenArea {
                let newY = SCContext.screen!.frame.height - nsRect.size.height - nsRect.origin.y
                conf.sourceRect = CGRect(x: nsRect.origin.x, y: newY, width: nsRect.size.width, height: nsRect.size.height)
                if #available(macOS 14.0, *) {
                    conf.width = Int(conf.sourceRect.width) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
                    conf.height = Int(conf.sourceRect.height) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
                } else {
                    guard let pointPixelScaleOld = (SCContext.screen ?? SCContext.getSCDisplayWithMouse()!).nsScreen?.backingScaleFactor else { return }
                    conf.width = Int(conf.sourceRect.width) * (highRes == 2 ? Int(pointPixelScaleOld) : 1)
                    conf.height = Int(conf.sourceRect.height) * (highRes == 2 ? Int(pointPixelScaleOld) : 1)
                }
            }
        }
        
        let encoderIsH265 = (encoder.rawValue == Encoder.h265.rawValue) || recordHDR
        if !audioOnly && !encoderIsH265 {
            var session: VTCompressionSession?
            let status = VTCompressionSessionCreate(
                allocator: nil,
                width: Int32(conf.width),
                height: Int32(conf.height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true] as CFDictionary,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: nil,
                refcon: nil,
                compressionSessionOut: &session
            )
            
            if status != noErr {
                let button = showAlertSyncOnMainThread(
                    level: .critical,
                    title: "Encoder Warning",
                    message: "VideoToolbox H.264 hardware encoder doesn't support the current resolution.\nContinue with a software encoder will significantly increase the CPU usage.\n\nWould you like to use H.265 instead?".local,
                    button1: "Use H.265",
                    button2: "Continue with H.264"
                )
                if button == .alertFirstButtonReturn { ud.setValue(Encoder.h265.rawValue, forKey: "encoder") }
            }
        }
        
        SCContext.stream = SCStream(filter: filter, configuration: conf, delegate: self)
        do {
            try SCContext.stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            if #available(macOS 13, *) { try SCContext.stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global()) }
            if !audioOnly {
                initVideo(conf: conf)
            } else {
                //SCContext.startTime = Date.now
                if recordMic { startMicRecording() }
            }
            try await SCContext.stream.startCapture()
        } catch {
            assertionFailure("capture failed".local)
            return
        }
        if !audioOnly { registerGlobalMouseMonitor() }
        DispatchQueue.main.async { updateStatusBar() }
        if preventSleep { SleepPreventer.shared.preventSleep(reason: "Screen recording in progress") }
    }

    func prepareAudioRecording() {
        var fileEnding = audioFormat.rawValue
        var fileType = AVFileType.m4a
        let encorder = fileEnding == AudioFormat.mp3.rawValue ? "aac" : fileEnding
        switch fileEnding { // todo: I'd like to store format info differently
            case AudioFormat.mp3.rawValue: fallthrough
            case AudioFormat.aac.rawValue: fallthrough
            case AudioFormat.alac.rawValue: fileEnding = "m4a"
            case AudioFormat.flac.rawValue: fileEnding = "flac"; fileType = .caf
            case AudioFormat.opus.rawValue: fileEnding = "ogg"; fileType = .caf
            default: assertionFailure("loaded unknown audio format: ".local + fileEnding)
        }
        let path = SCContext.getFilePath()
        if recordMic && SCContext.streamType == .systemaudio {
            SCContext.filePath = "\(path).qma"
            SCContext.filePath1 = "\(path).qma/sys.\(fileEnding)"
            SCContext.filePath2 = "\(path).qma/mic.\(fileEnding)"
            let infoJsonURL = "\(path).qma/info.json".url
            let jsonString = "{\"format\": \"\(fileEnding)\", \"encoder\": \"\(encorder)\", \"exportMP3\": \(audioFormat.rawValue == AudioFormat.mp3.rawValue), \"sysVol\": 1.0, \"micVol\": 1.0}"
            try? fd.createDirectory(at: SCContext.filePath.url, withIntermediateDirectories: true, attributes: nil)
            try? jsonString.write(to: infoJsonURL, atomically: true, encoding: .utf8)
            
            SCContext.audioFile = try! AVAudioFile(forWriting: SCContext.filePath1.url, settings: SCContext.updateAudioSettings(), commonFormat: .pcmFormatFloat32, interleaved: false)

            let sampleRate = SCContext.getSampleRate() ?? 48000
            let settings = SCContext.updateAudioSettings(rate: sampleRate)
            SCContext.vW = try? AVAssetWriter.init(outputURL: SCContext.filePath2.url, fileType: fileType)
            SCContext.micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
            SCContext.micInput.expectsMediaDataInRealTime = true
            if SCContext.vW.canAdd(SCContext.micInput) { SCContext.vW.add(SCContext.micInput) }
            // Enable fragmented writing to prevent corruption on unexpected termination
            SCContext.vW.movieFragmentInterval = CMTime(seconds: 0.5, preferredTimescale: 1000)
            SCContext.vW.startWriting()
            //SCContext.audioFile2 = try! AVAudioFile(forWriting: SCContext.filePath2.url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } else {
            SCContext.filePath = "\(path).\(fileEnding)"
            SCContext.filePath1 = SCContext.filePath
            SCContext.audioFile = try! AVAudioFile(forWriting: SCContext.filePath.url, settings: SCContext.updateAudioSettings(), commonFormat: .pcmFormatFloat32, interleaved: false)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
    var isMainScreen: Bool {
        guard let id = self.displayID else { return false }
        return (CGDisplayIsMain(id) == 1)
    }
}

extension SCDisplay {
    var nsScreen: NSScreen? {
        return NSScreen.screens.first(where: { $0.displayID == self.displayID })
    }
}

extension AppDelegate {
    func initVideo(conf: SCStreamConfiguration) {
        SCContext.startTime = nil
        SCContext.sessionStarted = false  // Reset session state for new recording
        debugLog("initVideo: sessionStarted reset to false")

        let fileEnding = videoFormat.rawValue
        var fileType: AVFileType?
        switch fileEnding {
            case VideoFormat.mov.rawValue: fileType = AVFileType.mov
            case VideoFormat.mp4.rawValue: fileType = AVFileType.mp4
            default: assertionFailure("loaded unknown video format".local)
        }

        if remuxAudio && recordMic && recordWinSound {
            SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding).\(fileEnding).\(fileEnding)"
        } else {
            SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding)"
        }
        SCContext.vW = try? AVAssetWriter.init(outputURL: SCContext.filePath.url, fileType: fileType!)
        let encoderIsH265 = (encoder.rawValue == Encoder.h265.rawValue) || recordHDR
        let fpsMultiplier: Double = Double(frameRate)/8
        let encoderMultiplier: Double = encoderIsH265 ? 0.5 : 0.9
        let resolution = Double(max(600, conf.width)) * Double(max(600, conf.height))
        var qualityMultiplier = 1 - (log10(sqrt(resolution) * fpsMultiplier) / 5)
        switch videoQuality {
            case 0.3: qualityMultiplier = max(0.1, qualityMultiplier)
            case 0.7: qualityMultiplier = max(0.4, min(0.6, qualityMultiplier * 3))
            default: qualityMultiplier = 1.0
        }
        let h264Level = AVVideoProfileLevelH264HighAutoLevel
        let h265Level = recordHDR ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel

        let targetBitrate = resolution * fpsMultiplier * encoderMultiplier * qualityMultiplier * (recordHDR ? 2 : 1)
        print("framerate set in app: \(frameRate)")
        print("target bitrate: \(targetBitrate/1000000)")

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: encoderIsH265 ? ((withAlpha && !recordHDR) ? AVVideoCodecType.hevcWithAlpha : AVVideoCodecType.hevc) : AVVideoCodecType.h264,
            // yes, not ideal if we want more than these encoders in the future, but it's ok for now
            AVVideoWidthKey: conf.width,
            AVVideoHeightKey: conf.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: encoderIsH265 ? h265Level : h264Level,
                AVVideoAverageBitRateKey: max(200000, Int(targetBitrate)),
                AVVideoExpectedSourceFrameRateKey: frameRate,
            ] as [String : Any]
        ]
        
        if !recordHDR {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2] as [String : Any]
        }
        
        SCContext.vwInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        SCContext.vwInput.expectsMediaDataInRealTime = true
        
        if SCContext.vW.canAdd(SCContext.vwInput) { SCContext.vW.add(SCContext.vwInput) }

        if #available(macOS 13, *) {
            SCContext.awInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: SCContext.updateAudioSettings())
            SCContext.awInput.expectsMediaDataInRealTime = true
            if SCContext.vW.canAdd(SCContext.awInput) { SCContext.vW.add(SCContext.awInput) }
        }

        if recordMic {
            let sampleRate = SCContext.getSampleRate() ?? 48000
            let settings = SCContext.updateAudioSettings(rate: sampleRate)

            SCContext.micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
            SCContext.micInput.expectsMediaDataInRealTime = true
            if SCContext.vW.canAdd(SCContext.micInput) { SCContext.vW.add(SCContext.micInput) }
            startMicRecording()
        }

        // Fragmented MP4 keeps the file playable if recording is interrupted.
        // Skip whenever the writer has non-video inputs: AVAssetWriter's fragment-boundary
        // synchronization requires every input to remain ready at each boundary, but SCStream
        // feeds video/audio sample buffers on independent callbacks at different rates. After
        // the first ~1s fragment, an audio input's isReadyForMoreMediaData stays false and
        // subsequent samples are silently dropped (RecordEngine.swift:653 / mic append paths).
        // Confirmed: ffprobe on three failed v1.7.3 recordings showed identical 47 AAC frames
        // (=1.0s at 48kHz) regardless of how long the user recorded.
        // Skip conditions:
        //   - HDR: HEVC Main10 triggers VTVideoEncoderMalfunctionErr (-16341)
        //   - Any audio input (mic or system sound): fragment alignment stall
        let hasAnyAudio = ud.bool(forKey: "recordMic") || ud.bool(forKey: "recordWinSound")
        if !recordHDR && !hasAnyAudio {
            SCContext.vW.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 1000)
            debugLog("initVideo: fragmented MP4 enabled (1s interval, screen-only)")
        } else if recordHDR {
            debugLog("initVideo: fragmented MP4 skipped (HDR mode)")
        } else {
            debugLog("initVideo: fragmented MP4 skipped (audio inputs present)")
        }

        SCContext.vW.startWriting()
        debugLog("initVideo: vW.startWriting() - filePath: \(SCContext.filePath ?? "nil")")
    }

    func startMicRecording() {
        if micDevice == "default" {
            if enableAEC {
                var level = AUVoiceIOOtherAudioDuckingLevel.mid
                switch AECLevel {
                    case "min": level = .min
                    case "max": level = .max
                    default: level = .mid
                }
                try? SCContext.AECEngine.startAudioStream(enableAEC: enableAEC, duckingLevel: level, audioBufferHandler: { pcmBuffer in
                    if SCContext.isPaused || SCContext.startTime == nil { return }
                    // Check microphone mute state before appending audio data
                    if SCContext.micInput.isReadyForMoreMediaData {
                        if !SCContext.isMicMuted {
                            SCContext.micInput.append(pcmBuffer.asSampleBuffer!)
                        } else if let silent = SCContext.makeSilentSampleBuffer(matching: pcmBuffer) {
                            SCContext.micInput.append(silent)
                        }
                    }
                })
            } else {
                let input = SCContext.audioEngine.inputNode
                let inputFormat = input.inputFormat(forBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
                    if SCContext.isPaused || SCContext.startTime == nil { return }
                    // Check microphone mute state before appending audio data
                    if SCContext.micInput.isReadyForMoreMediaData {
                        if !SCContext.isMicMuted {
                            SCContext.micInput.append(buffer.asSampleBuffer!)
                        } else if let silent = SCContext.makeSilentSampleBuffer(matching: buffer) {
                            SCContext.micInput.append(silent)
                        }
                    }
                }
                try! SCContext.audioEngine.start()
            }
        } else {
            AudioRecorder.shared.setupAudioCapture()
            AudioRecorder.shared.start()
        }
    }
    
    func outputVideoEffectDidStart(for stream: SCStream) {
        DispatchQueue.main.async { camWindow.close() }
        print("[Presenter Overlay ON]")
        isPresenterON = true
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(poSafeDelay)) {
            self.isCameraReady = true
        }
    }
    
    func outputVideoEffectDidStop(for stream: SCStream) {
        print("[Presenter Overlay OFF]")
        presenterType = "OFF"
        isPresenterON = false
        isCameraReady = false
        DispatchQueue.main.async {
            if SCContext.stream != nil { camWindow.orderFront(self) }
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        if SCContext.saveFrame, let imageBuffer = sampleBuffer.imageBuffer {
            SCContext.saveFrame = false
            
            var ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let url = "\(SCContext.getFilePath(capture: true)).png".url
            if !recordHDR {
                sampleBuffer.nsImage?.saveToFile(url)
            } else {
                let context = CIContext()
                
                // Create the HEIF destination with the correct UTI
                //            if let destination = url? {
                // Specify format and color space (assuming default settings here)
                //                let format = CIFormat.rgb10
                let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
                
                // let colorSpace = ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
                
                // Image exposure needs to be increased by one stop to match the original
                ciImage = ciImage.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 1.0])
                
                
                
                
                
                //                context.writeHEIF10Representation(of: ciImage, to: destination as! URL, colorSpace: colorSpace)
                do{
                    // try context.writeHEIF10Representation(of:ciImage,
                    //                                       to:url,
                    //                                       colorSpace:colorSpace,
                    //                                       options: [
                    //     kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0
                    if #available(macOS 14.0, *) {
                        try context.writePNGRepresentation(of:ciImage,
                                                           to:url,
                                                           format: .RGB10,
                                                           colorSpace:colorSpace
                        )
                    } else {
                        // Fallback on earlier versions
                        print("RGB10 PNG not supported on this macOS version")
                        try context.writePNGRepresentation(of:ciImage,
                                                           to:url,
                                                           format: .RGBA8,
                                                           colorSpace:colorSpace)
                    }
                    //        try context.writePNGRepresentation(of:outImage, to:outURL, format: .RGBA16,colorSpace:colorSpace,options:[:])
                } catch let error {
                    // Handle the error case
                    print("Error: \(error)")
                }
                //                CGImageDestinationFinalize(destination)
            }
        }
        if SCContext.isPaused { return }
        guard sampleBuffer.isValid else { return }
        var SampleBuffer = sampleBuffer
        if SCContext.isResume {
            SCContext.isResume = false
            var pts = CMSampleBufferGetPresentationTimeStamp(SampleBuffer)
            guard let last = SCContext.lastPTS else { return }
            if last.flags.contains(CMTimeFlags.valid) {
                if SCContext.timeOffset.flags.contains(CMTimeFlags.valid) { pts = CMTimeSubtract(pts, SCContext.timeOffset) }
                let off = CMTimeSubtract(pts, last)
                print("adding \(CMTimeGetSeconds(off)) to \(CMTimeGetSeconds(SCContext.timeOffset)) (pts \(CMTimeGetSeconds(SCContext.timeOffset)))")
                if SCContext.timeOffset.value == 0 { SCContext.timeOffset = off } else { SCContext.timeOffset = CMTimeAdd(SCContext.timeOffset, off) }
            }
            SCContext.lastPTS?.flags = []
        }
        switch outputType {
        case .screen:
            if (SCContext.screen == nil && SCContext.window == nil && SCContext.application == nil) || SCContext.streamType == .systemaudio { break }
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(SampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first else { return }
            guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue),
                  status == .complete else { return }

            if SCContext.vW != nil && SCContext.vW?.status == .writing, SCContext.startTime == nil {
                SCContext.startTime = Date.now
                SCContext.vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(SampleBuffer))
                SCContext.sessionStarted = true
                debugLog("Recording started: first frame received, session started")
            }
            if (SCContext.timeOffset.value > 0) { SampleBuffer = SCContext.adjustTime(sample: SampleBuffer, by: SCContext.timeOffset) ?? sampleBuffer }
            var pts = CMSampleBufferGetPresentationTimeStamp(SampleBuffer)
            let dur = CMSampleBufferGetDuration(SampleBuffer)
            if (dur.value > 0) { pts = CMTimeAdd(pts, dur) }
            if frameQueue.getArray().contains(where: { $0 >= pts }) { print("Skip this frame"); return } else { frameQueue.append(pts) }
            SCContext.lastPTS = pts
            if SCContext.vwInput.isReadyForMoreMediaData {
                if #available(macOS 14.2, *) {
                    if let rect = attachments[.presenterOverlayContentRect] as? [String: Any]{
                        var type = "np"
                        let off = (rect["X"] as! CGFloat == .infinity)
                        let small = (rect["X"] as! CGFloat == 0.0)
                        let big = (!off && !small)
                        if off { type = "OFF" } else if small { type = "Small" } else if big { type = "Big" }
                        if type != presenterType {
                            print("Presenter Overlay set to \"\(type)\"!")
                            isCameraReady = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(poSafeDelay)) {
                                self.isCameraReady = true
                            }
                            presenterType = type
                        }
                    }
                }
                if isPresenterON && !isCameraReady { break }
                if SCContext.firstFrame == nil { SCContext.firstFrame = SampleBuffer }
                SCContext.vwInput.append(SampleBuffer)
            }
            break
        case .audio:
            if SCContext.streamType == .systemaudio { // write directly to file if not video recording
                hideMousePointer = true
                if SCContext.vW != nil && SCContext.vW?.status == .writing, SCContext.startTime == nil {
                    SCContext.vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(SampleBuffer))
                    SCContext.sessionStarted = true
                }
                if SCContext.startTime == nil { SCContext.startTime = Date.now }
                guard let samples = SampleBuffer.asPCMBuffer else { return }
                do { try SCContext.audioFile?.write(from: samples) }
                catch { assertionFailure("audio file writing issue".local) }
            } else {
                if SCContext.lastPTS == nil { return }
                if SCContext.awInput.isReadyForMoreMediaData { SCContext.awInput.append(SampleBuffer) }
            }
#if compiler(>=6.0)
        case .microphone:
            break
#endif
        @unknown default:
            assertionFailure("unknown stream type".local)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { // stream error
        print("closing stream with error:\n".local, error,
              "\nthis might be due to the window closing or the user stopping from the sonoma ui".local)
        DispatchQueue.main.async {
            SCContext.stream = nil
            SCContext.stopRecording()
        }
    }
}

class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = AudioRecorder()
    private var captureSession: AVCaptureSession!
    private var audioInput: AVCaptureDeviceInput!
    private var audioDataOutput: AVCaptureAudioDataOutput!

    func setupAudioCapture() {
        captureSession = AVCaptureSession()

        // Get the default audio device (microphone)
        guard let audioDevice = SCContext.getCurrentMic() else {
            print("Unable to access microphone")
            return
        }
        
        // Create audio input
        do {
            audioInput = try AVCaptureDeviceInput(device: audioDevice)
        } catch {
            print("Unable to create audio input: \(error)")
            return
        }
        
        // Add audio input to capture session
        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        } else {
            print("Unable to add audio input to capture session")
            return
        }

        // Create audio data output
        audioDataOutput = AVCaptureAudioDataOutput()
        let audioQueue = DispatchQueue(label: "audioQueue")
        audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)
        
        // Add audio data output to capture session
        if captureSession.canAddOutput(audioDataOutput) {
            captureSession.addOutput(audioDataOutput)
        } else {
            print("Unable to add audio data output to capture session")
            return
        }
    }
    
    func start() {
        if let session = captureSession {
            session.startRunning()
        }
    }
    
    func stop() {
        if let session = captureSession {
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if SCContext.isPaused || SCContext.startTime == nil { return }
        // Check microphone mute state before appending audio data
        if SCContext.micInput.isReadyForMoreMediaData {
            if !SCContext.isMicMuted {
                SCContext.micInput.append(sampleBuffer)
            } else if let silent = SCContext.makeSilentSampleBuffer(matching: sampleBuffer) {
                SCContext.micInput.append(silent)
            }
        }
    }
}

// https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
// For Sonoma updated to https://developer.apple.com/forums/thread/727709
extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? self.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard let absd = self.formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
    
    var nsImage: NSImage? {
        return autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let ciContext = CIContext()
            if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
            return nil
        }
    }
}

// Based on https://gist.github.com/aibo-cora/c57d1a4125e145e586ecb61ebecff47c
extension AVAudioPCMBuffer {
    var asSampleBuffer: CMSampleBuffer? {
        let asbd = self.format.streamDescription
        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil

        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(self.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: self.mutableAudioBufferList
        ) == noErr else { return nil }

        return sampleBuffer
    }
}
// MARK: - Webcam + screen deterministic logic
// WEBCAM_SCREEN_PURE_HELPERS_BEGIN

struct WebcamScreenLayout: Equatable {
    enum Position: String, CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    var position: Position = .bottomRight
    var widthFraction: Double = 0.25
    var mirrored = false

    func rect(in size: CGSize) -> CGRect {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return .zero }
        let margin = min(size.width, size.height) * 0.025
        let availableWidth = max(0, size.width - margin * 2)
        let availableHeight = max(0, size.height - margin * 2)
        let requestedFraction = widthFraction.isFinite ? widthFraction : 0.25
        let requestedWidth = availableWidth * min(0.45, max(0.10, requestedFraction))
        let width = min(requestedWidth, availableHeight * (16.0 / 9.0))
        let height = width * (9.0 / 16.0)
        let x = position == .topLeft || position == .bottomLeft
            ? margin
            : size.width - margin - width
        let y = position == .topLeft || position == .topRight
            ? size.height - margin - height
            : margin
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct WebcamScreenOutputSize: Equatable {
    let width: Int
    let height: Int

    static func capped(width: Int, height: Int, maximumWidth: Int = 1920, maximumHeight: Int = 1080) -> WebcamScreenOutputSize? {
        guard width >= 16, height >= 16, maximumWidth >= 16, maximumHeight >= 16 else { return nil }
        let scale = min(1, Double(maximumWidth) / Double(width), Double(maximumHeight) / Double(height))
        let cappedWidth = max(16, Int((Double(width) * scale).rounded(.down)) & ~1)
        let cappedHeight = max(16, Int((Double(height) * scale).rounded(.down)) & ~1)
        guard cappedWidth.isMultiple(of: 2), cappedHeight.isMultiple(of: 2),
              cappedWidth <= maximumWidth, cappedHeight <= maximumHeight else { return nil }
        return WebcamScreenOutputSize(width: cappedWidth, height: cappedHeight)
    }
}

struct WebcamScreenTimedValue<Value> {
    let hostTime: TimeInterval
    let value: Value
}

struct WebcamScreenRecentBuffer<Value> {
    private(set) var values = [WebcamScreenTimedValue<Value>]()
    let capacity: Int

    init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ value: Value, at hostTime: TimeInterval) {
        guard hostTime.isFinite else { return }
        values.append(WebcamScreenTimedValue(hostTime: hostTime, value: value))
        values.sort { $0.hostTime < $1.hostTime }
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    func latest(notAfter hostTime: TimeInterval) -> WebcamScreenTimedValue<Value>? {
        values.last { $0.hostTime <= hostTime }
    }

    mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
    }
}

struct WebcamScreenPendingFrame<Value> {
    private(set) var value: Value?

    mutating func holdComplete(_ value: Value) {
        self.value = value
    }

    mutating func ignoreIdle() {
        // Idle carries no new image; keep a complete frame until its clock is available.
    }
    mutating func takeWhenClockReady() -> Value? {
        defer { value = nil }
        return value
    }

    mutating func clear() {
        value = nil
    }
}

struct WebcamScreenTimeline {
    private(set) var origin: TimeInterval?
    private(set) var totalPaused: TimeInterval = 0
    private(set) var pauseStartedAt: TimeInterval?
    private(set) var pausedIntervals = [Range<TimeInterval>]()

    mutating func start(at hostTime: TimeInterval) {
        guard hostTime.isFinite else { return }
        origin = hostTime
        totalPaused = 0
        pauseStartedAt = nil
        pausedIntervals.removeAll(keepingCapacity: true)
    }

    mutating func pause(at hostTime: TimeInterval) {
        guard let origin, pauseStartedAt == nil, hostTime.isFinite else { return }
        pauseStartedAt = max(origin, hostTime)
    }

    mutating func resume(at hostTime: TimeInterval) {
        guard let start = pauseStartedAt, hostTime.isFinite else { return }
        let end = max(start, hostTime)
        totalPaused += end - start
        if end > start { pausedIntervals.append(start..<end) }
        pauseStartedAt = nil
    }

    func elapsed(at hostTime: TimeInterval) -> TimeInterval? {
        guard let origin, hostTime.isFinite else { return nil }
        let activeHostTime = min(hostTime, pauseStartedAt ?? hostTime)
        let pausedDuration = pausedIntervals.reduce(0.0) { total, interval in
            let overlapEnd = min(activeHostTime, interval.upperBound)
            return total + max(0, overlapEnd - interval.lowerBound)
        }
        let elapsed = activeHostTime - origin - pausedDuration
        guard elapsed.isFinite, elapsed >= 0 else { return nil }
        return elapsed
    }

    func isPaused(at hostTime: TimeInterval) -> Bool {
        if let pauseStartedAt, hostTime >= pauseStartedAt { return true }
        return pausedIntervals.contains { $0.contains(hostTime) }
    }

    func overlapsPause(from hostTime: TimeInterval, duration: TimeInterval) -> Bool {
        guard hostTime.isFinite else { return true }
        guard duration.isFinite else { return isPaused(at: hostTime) }
        if isPaused(at: hostTime) { return true }
        let end = hostTime + max(0, duration)
        guard end.isFinite else { return true }
        guard end > hostTime else { return false }
        if pausedIntervals.contains(where: { hostTime < $0.upperBound && end > $0.lowerBound }) {
            return true
        }
        if let pauseStartedAt, hostTime < pauseStartedAt, end > pauseStartedAt {
            return true
        }
        return false
    }
}

struct WebcamScreenMonotonicPTS {
    private(set) var last: TimeInterval?

    mutating func accept(_ value: TimeInterval) -> Bool {
        guard value.isFinite, value >= 0,
              last.map({ value > $0 }) ?? true else { return false }
        last = value
        return true
    }

    mutating func reset() {
        last = nil
    }
}

struct WebcamScreenBackpressure {
    private(set) var blockedSince: TimeInterval?
    let timeout: TimeInterval

    init(timeout: TimeInterval = 5) {
        self.timeout = max(0.1, timeout)
    }

    mutating func timedOut(isReady: Bool, at hostTime: TimeInterval) -> Bool {
        guard hostTime.isFinite else { return false }
        if isReady {
            blockedSince = nil
            return false
        }
        if blockedSince == nil { blockedSince = hostTime }
        return hostTime - (blockedSince ?? hostTime) >= timeout
    }

    mutating func reset() {
        blockedSince = nil
    }
}

final class WebcamScreenCompositor {
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(context: CIContext = CIContext(options: [.cacheIntermediates: false])) {
        self.context = context
    }

    func compositeImage(
        screen: CVPixelBuffer,
        camera: CVPixelBuffer,
        layout: WebcamScreenLayout,
        outputSize: CGSize
    ) -> CIImage? {
        guard outputSize.width.isFinite, outputSize.height.isFinite,
              outputSize.width >= 2, outputSize.height >= 2 else { return nil }
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let screenImage = CIImage(cvPixelBuffer: screen)
        let cameraImage = CIImage(cvPixelBuffer: camera)
        guard !screenImage.extent.isEmpty, !cameraImage.extent.isEmpty else { return nil }

        let screenScale = CGAffineTransform(
            scaleX: outputSize.width / screenImage.extent.width,
            y: outputSize.height / screenImage.extent.height
        )
        let canvas = screenImage
            .transformed(by: screenScale)
            .cropped(to: outputRect)

        let source = cameraImage.extent
        let sourceAspect = source.width / source.height
        let targetAspect = 16.0 / 9.0
        let cropRect: CGRect
        if sourceAspect > targetAspect {
            let cropWidth = source.height * targetAspect
            cropRect = CGRect(x: source.midX - cropWidth / 2, y: source.minY, width: cropWidth, height: source.height)
        } else {
            let cropHeight = source.width / targetAspect
            cropRect = CGRect(x: source.minX, y: source.midY - cropHeight / 2, width: source.width, height: cropHeight)
        }

        let pipRect = layout.rect(in: outputSize)
        guard !pipRect.isEmpty, cropRect.width > 0, cropRect.height > 0 else { return nil }
        var pip = cameraImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        if layout.mirrored {
            pip = pip.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: cropRect.width, ty: 0))
        }
        pip = pip
            .transformed(by: CGAffineTransform(scaleX: pipRect.width / cropRect.width, y: pipRect.height / cropRect.height))
            .transformed(by: CGAffineTransform(translationX: pipRect.minX, y: pipRect.minY))
        return pip.composited(over: canvas).cropped(to: outputRect)
    }

    func render(_ image: CIImage, into pixelBuffer: CVPixelBuffer, outputSize: CGSize) {
        context.render(
            image,
            to: pixelBuffer,
            bounds: CGRect(origin: .zero, size: outputSize),
            colorSpace: colorSpace
        )
    }

    func makeImage(_ image: CIImage, outputSize: CGSize) -> NSImage? {
        let bounds = CGRect(origin: .zero, size: outputSize)
        guard let cgImage = context.createCGImage(image, from: bounds, format: .BGRA8, colorSpace: colorSpace) else { return nil }
        return NSImage(cgImage: cgImage, size: outputSize)
    }

    static func makePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        guard width > 0, height > 0 else { return nil }
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey: 3] as CFDictionary
        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes, pixelAttributes as CFDictionary, &pool) == kCVReturnSuccess else {
            return nil
        }
        return pool
    }
}

// WEBCAM_SCREEN_PURE_HELPERS_END

// WEBCAM_SCREEN_BACKEND_BEGIN
final class WebcamScreenRecorder: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, SCStreamDelegate, SCStreamOutput {
    static let shared = WebcamScreenRecorder()
    typealias State = WebcamRecorder.State

    @Published private(set) var state: State = .idle
    @Published private(set) var isBusy = false
    @Published private(set) var isPaused = false
    @Published private(set) var recordedDuration: TimeInterval = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var countdownRemaining = 0
    @Published private(set) var actualFormatDescription = ""

    private struct RecordingSettings {
        let fileType: AVFileType
        let fileExtension: String
        let requestedCodec: AVVideoCodecType
        let frameRate: Int
        let autoStopMinutes: Int
        let remuxAudio: Bool
        let showPreview: Bool
        let trimAfterRecord: Bool
        let preventSleep: Bool
        let hasMicrophone: Bool
        let hasSystemAudio: Bool
    }

    private struct WriterFinishResult {
        let success: Bool
        let error: String?
    }

    private struct RemuxResult {
        let outputURL: URL
        let warning: String?
    }

    private let queue = DispatchQueue(label: "QuickRecorder.WebcamScreenRecorder")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let compositor = WebcamScreenCompositor()
    private var backendState: State = .idle
    private var generation = UUID()
    private var publishedGeneration = UUID()

    private var cameraSession: AVCaptureSession?
    private var cameraDevice: AVCaptureDevice?
    private var microphoneDevice: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var microphoneOutput: AVCaptureAudioDataOutput?
    private var sessionObservers = [NSObjectProtocol]()
    private var screenStream: SCStream?
    private var screenClock: CMClock?
    private var pendingCompleteScreenFrame = WebcamScreenPendingFrame<CMSampleBuffer>()
    private var cameraClock: CMClock?
    private var screenStartInFlight = false
    private var screenStopInFlight = false
    private var stopAfterScreenStart = false
    private var captureCleanupCompletions = [() -> Void]()

    private var selectedCameraID = ""
    private var selectedMicrophoneID: String?
    private var selectedDisplayID: CGDirectDisplayID = 0
    private var selectedSCDisplay: SCDisplay?
    private var captureSystemAudio = false
    private var layout = WebcamScreenLayout()
    private var outputSize = WebcamScreenOutputSize(width: 2, height: 2)
    private var outputFPS = 30
    private var cameraFrames = WebcamScreenRecentBuffer<CVPixelBuffer>(capacity: 4)
    private var latestCompleteScreen: CVPixelBuffer?
    private var latestCompleteScreenHostTime: TimeInterval?

    private var frameTimer: DispatchSourceTimer?
    private var startupTimer: DispatchSourceTimer?
    private var countdownTimer: DispatchSourceTimer?
    private var writerStartTimer: DispatchSourceTimer?
    private var countdownValue = 0
    private var lastPreviewHostTime: TimeInterval = 0
    private var previewPublishPending = false
    private var lastDurationPublishHostTime: TimeInterval = 0
    private var lastCompositeImage: NSImage?

    private var recordingSettings: RecordingSettings?
    private var recordingURL: URL?
    private var writerURL: URL?
    private var outputReservationURL: URL?
    private var writerReservationURL: URL?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var writerStarted = false
    private var writerOutputOwned = false
    private var writerFinishRequested = false
    private var writerFinishDone = false
    private var captureFinishDone = false
    private var remuxStarted = false
    private var finishResult: WriterFinishResult?
    private var remuxResult: RemuxResult?
    private var timeline = WebcamScreenTimeline()
    private var lastVideoPTS = WebcamScreenMonotonicPTS()
    private var lastMicrophonePTS = WebcamScreenMonotonicPTS()
    private var lastSystemAudioPTS = WebcamScreenMonotonicPTS()
    private var videoBackpressure = WebcamScreenBackpressure()
    private var microphoneBackpressure = WebcamScreenBackpressure()
    private var systemAudioBackpressure = WebcamScreenBackpressure()
    private var effectiveDuration: TimeInterval = 0
    private var runtimeFailureMessage: String?
    private var sharedRecordingStateClaimed = false
    private var sleepAssertionHeld = false

    private override init() {
        super.init()
        queue.setSpecific(key: queueKey, value: 1)
    }

    func startPreview(cameraID: String, microphoneID: String? = nil, displayID: CGDirectDisplayID, captureSystemAudio: Bool) {
        let token = UUID()
        let reserve: () -> (accepted: Bool, snapshot: (previewImage: NSImage?, format: String, countdown: Int)) = {
            let snapshot = (
                previewImage: self.previewImage,
                format: self.actualFormatDescription,
                countdown: self.countdownRemaining
            )
            let canReconfigure = self.state == .preparing || self.state == .previewing
            guard canReconfigure || self.state == .idle else { return (false, snapshot) }
            if self.state == .idle {
                guard SCContext.streamType == nil, !WebcamRecorder.shared.isBusy else {
                    self.errorMessage = "Another recording is already active.".local
                    return (false, snapshot)
                }
                self.isBusy = true
                self.isPaused = false
                self.recordedDuration = 0
                self.countdownRemaining = 0
                self.errorMessage = nil
                self.previewImage = nil
                self.state = .preparing
            } else {
                self.state = .preparing
                self.previewImage = nil
                self.actualFormatDescription = ""
            }
            self.publishedGeneration = token
            return (true, snapshot)
        }
        let reservation = Thread.isMainThread ? reserve() : DispatchQueue.main.sync(execute: reserve)
        guard reservation.accepted else { return }
        let reservationSnapshot = reservation.snapshot


        let microphone = microphoneID.flatMap { $0.isEmpty ? nil : $0 }
        queue.async {
            let currentState = self.backendState
            guard currentState == .idle || currentState == .preparing || currentState == .previewing else {
                let currentGeneration = self.generation
                let currentCountdown = self.countdownValue
                let snapshot = reservationSnapshot
                DispatchQueue.main.async {
                    guard self.publishedGeneration == token else { return }
                    self.publishedGeneration = currentGeneration
                    self.state = currentState
                    self.isBusy = currentState != .idle
                    self.isPaused = currentState == .paused
                    self.countdownRemaining = currentCountdown
                    self.previewImage = snapshot.previewImage
                    self.actualFormatDescription = snapshot.format
                    self.errorMessage = "Another recording is already active.".local
                }
                return
            }
            self.generation = token
            self.backendState = .preparing
            self.stopCaptureGraph {
                guard self.generation == token, self.backendState == .preparing else { return }
                self.selectedCameraID = cameraID
                self.selectedMicrophoneID = microphone
                self.selectedDisplayID = displayID
                self.captureSystemAudio = captureSystemAudio
                self.cameraFrames.removeAll()
                self.latestCompleteScreen = nil
                self.latestCompleteScreenHostTime = nil
                self.lastPreviewHostTime = 0
                self.lastCompositeImage = nil
                self.runtimeFailureMessage = nil
                self.publishError(nil, token: token)
                self.publishCountdown(0, token: token)
                self.publishFormat("", token: token)
                guard !cameraID.isEmpty else {
                    self.failPreparation("No camera is selected.".local, token: token)
                    return
                }
                guard #available(macOS 13.0, *) else {
                    self.failPreparation("Webcam + Screen recording requires macOS 13 or later.".local, token: token)
                    return
                }
                self.startStartupWatchdog(token: token)
                self.authorizeCamera(token: token)
            }
        }
    }

    func updateLayout(_ layout: WebcamScreenLayout) {
        queue.async {
            guard self.backendState == .idle || self.backendState == .preparing || self.backendState == .previewing else { return }
            self.layout = layout
            if let screen = self.latestCompleteScreen,
               let camera = self.cameraFrames.latest(notAfter: self.hostNow())?.value,
               let image = self.compositor.compositeImage(
                   screen: screen,
                   camera: camera,
                   layout: self.layout,
                   outputSize: CGSize(width: CGFloat(self.outputSize.width), height: CGFloat(self.outputSize.height))
               ) {
                self.publishCompositePreview(image, at: self.hostNow(), token: self.generation)
            }
        }
    }

    func startRecording(autoStopMinutes: Int = 0, remuxAudio: Bool = true) {
        queue.async {
            let token = self.generation
            guard self.backendState == .previewing else { return }
            let selectedFormat = UserDefaults.standard.string(forKey: "videoFormat") ?? VideoFormat.mp4.rawValue
            let fileExtension = selectedFormat == VideoFormat.mov.rawValue ? VideoFormat.mov.rawValue : VideoFormat.mp4.rawValue
            let encoder = UserDefaults.standard.string(forKey: "encoder") ?? Encoder.h265.rawValue
            let settings = RecordingSettings(
                fileType: fileExtension == VideoFormat.mov.rawValue ? .mov : .mp4,
                fileExtension: fileExtension,
                requestedCodec: encoder == Encoder.h264.rawValue ? .h264 : .hevc,
                frameRate: self.outputFPS,
                autoStopMinutes: max(0, autoStopMinutes),
                remuxAudio: remuxAudio,
                showPreview: UserDefaults.standard.bool(forKey: "showPreview"),
                trimAfterRecord: UserDefaults.standard.bool(forKey: "trimAfterRecord"),
                preventSleep: UserDefaults.standard.bool(forKey: "preventSleep"),
                hasMicrophone: self.selectedMicrophoneID != nil,
                hasSystemAudio: self.captureSystemAudio
            )
            guard let reservation = self.reserveOutputURL(fileExtension: fileExtension) else {
                self.publishError("Recording folder does not exist or is not writable.".local, token: token)
                return
            }
            self.recordingSettings = settings
            self.recordingURL = reservation.url
            self.outputReservationURL = reservation.marker
            self.effectiveDuration = 0
            self.publishDuration(0, token: token)
            self.publishError(nil, token: token)
            self.publishCountdown(0, token: token)
            self.countdownValue = max(0, UserDefaults.standard.integer(forKey: "countdown"))
            if self.countdownValue > 0 {
                self.backendState = .countdown
                self.publishState(.countdown, token: token)
                self.publishCountdown(self.countdownValue, token: token)
                self.startCountdown(token: token)
            } else {
                self.beginRecording(token: token)
            }
        }
    }

    func pauseRecording() {
        queue.async {
            let token = self.generation
            let now = self.hostNow()
            switch self.backendState {
            case .recording:
                self.timeline.pause(at: now)
                self.backendState = .paused
                let elapsed = self.timeline.elapsed(at: now) ?? self.effectiveDuration
                self.effectiveDuration = elapsed
                self.publishDuration(elapsed, token: token)
                self.publishState(.paused, token: token)
                self.publishSharedPauseState(true, duration: elapsed, token: token)
            case .paused:
                self.timeline.resume(at: now)
                self.backendState = .recording
                self.publishState(.recording, token: token)
                let duration = self.timeline.elapsed(at: now) ?? self.effectiveDuration
                self.effectiveDuration = duration
                self.publishSharedPauseState(false, duration: duration, token: token)
            default:
                break
            }
        }
    }

    func stopRecording() {
        queue.async {
            let token = self.generation
            switch self.backendState {
            case .idle, .finishing:
                return
            case .preparing, .previewing, .countdown:
                self.beginFinish(token: token, cancellation: true)
            case .starting:
                self.beginFinish(token: token, cancellation: !self.writerStarted)
            case .recording, .paused:
                self.beginFinish(token: token, cancellation: false)
            }
        }
    }

    func cancelPreview() {
        queue.async {
            let token = self.generation
            switch self.backendState {
            case .preparing, .previewing, .countdown:
                self.beginFinish(token: token, cancellation: true)
            case .idle, .starting, .recording, .paused, .finishing:
                break
            }
        }
    }


    private func authorizeCamera(token: UUID) {
        guard generation == token, backendState == .preparing else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizeMicrophone(token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.queue.async {
                    guard self.generation == token, self.backendState == .preparing else { return }
                    if granted {
                        self.authorizeMicrophone(token: token)
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

    private func authorizeMicrophone(token: UUID) {
        guard generation == token, backendState == .preparing else { return }
        guard selectedMicrophoneID != nil else {
            configureCameraSession(token: token)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            configureCameraSession(token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                self.queue.async {
                    guard self.generation == token, self.backendState == .preparing else { return }
                    if granted {
                        self.configureCameraSession(token: token)
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

    private func configureCameraSession(token: UUID) {
        guard generation == token, backendState == .preparing else { return }
        guard let camera = SCContext.getCameras().first(where: { $0.uniqueID == selectedCameraID }) else {
            failPreparation("Selected camera is unavailable.".local, token: token)
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(cameraInput) else {
                session.commitConfiguration()
                failPreparation("Unable to add the camera input.".local, token: token)
                return
            }
            session.addInput(cameraInput)
            var microphone: AVCaptureDevice?
            if let microphoneID = selectedMicrophoneID {
                guard let selected = SCContext.getMicrophone().first(where: { $0.uniqueID == microphoneID }) else {
                    session.commitConfiguration()
                    failPreparation("Selected microphone is unavailable.".local, token: token)
                    return
                }
                let microphoneInput = try AVCaptureDeviceInput(device: selected)
                guard session.canAddInput(microphoneInput) else {
                    session.commitConfiguration()
                    failPreparation("Unable to add the microphone input.".local, token: token)
                    return
                }
                session.addInput(microphoneInput)
                microphone = selected
            }

            let video = AVCaptureVideoDataOutput()
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            video.alwaysDiscardsLateVideoFrames = true
            video.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(video) else {
                session.commitConfiguration()
                failPreparation("Unable to add the camera video output.".local, token: token)
                return
            }
            session.addOutput(video)

            var audio: AVCaptureAudioDataOutput?
            if microphone != nil {
                let output = AVCaptureAudioDataOutput()
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    failPreparation("Unable to add the microphone audio output.".local, token: token)
                    return
                }
                session.addOutput(output)
                audio = output
            }
            session.commitConfiguration()

            cameraSession = session
            cameraDevice = camera
            microphoneDevice = microphone
            videoOutput = video
            microphoneOutput = audio
            addCameraObservers(session: session, camera: camera, microphone: microphone, token: token)
            session.startRunning()
            guard session.isRunning else {
                failPreparation("Unable to start camera preview.".local, token: token)
                return
            }
            if #available(macOS 13.0, *) {
                cameraClock = session.synchronizationClock
            } else {
                failPreparation("Webcam + Screen recording requires macOS 13 or later.".local, token: token)
                return
            }
            guard cameraClock != nil else {
                failPreparation("Unable to synchronize camera and display clocks.".local, token: token)
                return
            }
            if #available(macOS 13.0, *) {
                configureScreenCapture(token: token)
            } else {
                failPreparation("Webcam + Screen recording requires macOS 13 or later.".local, token: token)
            }
        } catch {
            session.commitConfiguration()
            failPreparation(String(format: "Unable to create the camera input: %@".local, error.localizedDescription), token: token)
        }
    }

    private func addCameraObservers(session: AVCaptureSession, camera: AVCaptureDevice, microphone: AVCaptureDevice?, token: UUID) {
        sessionObservers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.queue.async {
                guard let self, self.generation == token, self.cameraSession === session else { return }
                self.handleCaptureFailure(error.map {
                    String(format: "Camera capture failed: %@".local, $0.localizedDescription)
                } ?? "Camera capture failed.".local)
            }
        })
        sessionObservers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: camera,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                guard let self, self.generation == token else { return }
                self.handleCaptureFailure("The camera was disconnected.".local)
            }
        })
        if let microphone {
            sessionObservers.append(NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: microphone,
                queue: nil
            ) { [weak self] _ in
                self?.queue.async {
                    guard let self, self.generation == token else { return }
                    self.handleCaptureFailure("The selected microphone was disconnected.".local)
                }
            })
        }
    }

    @available(macOS 13.0, *)
    private func configureScreenCapture(token: UUID) {
        guard generation == token, backendState == .preparing else { return }
        pendingCompleteScreenFrame.clear()
        screenClock = nil
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            self.queue.async {
                guard self.generation == token, self.backendState == .preparing else { return }
                guard let content else {
                    if let error, case SCStreamError.userDeclined = error {
                        self.failPreparation("Screen Recording permission is required for Webcam + Screen mode.".local, token: token)
                    } else {
                        let message = error.map { String(format: "Unable to access screen content: %@".local, $0.localizedDescription) }
                            ?? "Unable to access screen content.".local
                        self.failPreparation(message, token: token)
                    }
                    return
                }
                guard let display = content.displays.first(where: { $0.displayID == self.selectedDisplayID }) else {
                    self.failPreparation("The selected display is unavailable.".local, token: token)
                    return
                }
                guard let size = WebcamScreenOutputSize.capped(width: Int(display.width), height: Int(display.height)) else {
                    self.failPreparation("The selected display has an unsupported size.".local, token: token)
                    return
                }
                self.outputSize = size
                self.selectedSCDisplay = display
                let configuredFPS = UserDefaults.standard.integer(forKey: "frameRate")
                self.outputFPS = min(30, max(1, configuredFPS == 0 ? 30 : configuredFPS))
                let config = SCStreamConfiguration()
                config.width = size.width
                config.height = size.height
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.colorSpaceName = CGColorSpace.sRGB
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(self.outputFPS))
                config.queueDepth = 4
                config.showsCursor = UserDefaults.standard.bool(forKey: "showMouse")
                config.capturesAudio = self.captureSystemAudio
                if self.captureSystemAudio {
                    config.sampleRate = 48000
                    config.channelCount = 2
                }
                let excludedApplications = content.applications.filter {
                    $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: excludedApplications,
                    exceptingWindows: []
                )
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                do {
                    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                    if self.captureSystemAudio {
                        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
                    }
                } catch {
                    self.failPreparation(String(format: "Unable to configure screen capture: %@".local, error.localizedDescription), token: token)
                    return
                }
                self.screenStream = stream
                if let streamClock = stream.synchronizationClock {
                    self.screenClock = streamClock
                }
                self.screenStartInFlight = true
                let requestedCodec = UserDefaults.standard.string(forKey: "encoder") == Encoder.h264.rawValue ? "H.264" : "HEVC"
                let fileFormat = UserDefaults.standard.string(forKey: "videoFormat") == VideoFormat.mov.rawValue ? "MOV" : "MP4"
                self.publishFormat(
                    String(format: "Webcam + Screen output: %d × %d at %d fps (%@, %@)".local, size.width, size.height, self.outputFPS, fileFormat, requestedCodec),
                    token: token
                )
                stream.startCapture { error in
                    self.queue.async { self.screenStartCompleted(stream, token: token, error: error) }
                }
            }
        }
    }

    private func screenStartCompleted(_ stream: SCStream, token: UUID, error: Error?) {
        guard screenStream === stream else {
            if error == nil { stopOrphanStream(stream) }
            return
        }
        screenStartInFlight = false
        if stopAfterScreenStart || !captureCleanupCompletions.isEmpty || generation != token || backendState == .finishing {
            stopAfterScreenStart = false
            if error == nil {
                startScreenStop(stream)
            } else {
                screenStream = nil
                drainCaptureCleanupCompletions()
            }
            return
        }
        if let error {
            handleCaptureFailure(String(format: "Unable to start screen capture: %@".local, error.localizedDescription))
            return
        }
        guard #available(macOS 13.0, *), let streamClock = stream.synchronizationClock else {
            handleCaptureFailure("Unable to synchronize camera and display clocks.".local)
            return
        }
        screenClock = streamClock
        if let pending = pendingCompleteScreenFrame.takeWhenClockReady() {
            processScreenOutput(stream, sampleBuffer: pending, outputType: .screen)
        }
        startFrameTimer(token: token)
    }

    private func stopOrphanStream(_ stream: SCStream) {
        stream.stopCapture(completionHandler: nil)
    }

    private func startStartupWatchdog(token: UUID) {
        cancelTimer(&startupTimer)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        startupTimer = timer
        timer.schedule(deadline: .now() + 30)
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == token,
                  self.backendState == .preparing else { return }
            self.handleCaptureFailure("Webcam + Screen setup timed out. Please try again.".local)
        }
        timer.resume()
    }

    private func startFrameTimer(token: UUID) {
        cancelTimer(&frameTimer)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        frameTimer = timer
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(outputFPS), leeway: .milliseconds(3))
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == token else { return }
            self.renderTick(token: token)
        }
        timer.resume()
    }

    private func startCountdown(token: UUID) {
        cancelTimer(&countdownTimer)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        countdownTimer = timer
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == token, self.backendState == .countdown else { return }
            self.countdownValue = max(0, self.countdownValue - 1)
            self.publishCountdown(self.countdownValue, token: token)
            if self.countdownValue == 0 {
                self.cancelTimer(&self.countdownTimer)
                self.beginRecording(token: token)
            }
        }
        timer.resume()
    }

    private func beginRecording(token: UUID) {
        guard generation == token,
              (backendState == .previewing || backendState == .countdown),
              let settings = recordingSettings, let finalURL = recordingURL else { return }
        backendState = .starting
        publishState(.starting, token: token)
        publishCountdown(0, token: token)
        timeline = WebcamScreenTimeline()
        lastVideoPTS.reset()
        lastMicrophonePTS.reset()
        lastSystemAudioPTS.reset()
        videoBackpressure.reset()
        microphoneBackpressure.reset()
        systemAudioBackpressure.reset()
        writerStarted = false
        writerOutputOwned = false
        writerFinishRequested = false
        writerFinishDone = false
        captureFinishDone = false
        remuxStarted = false
        finishResult = nil
        remuxResult = nil
        runtimeFailureMessage = nil

        let needsRemux = settings.remuxAudio && settings.hasMicrophone && settings.hasSystemAudio
        if needsRemux {
            let rawName = "\(finalURL.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).\(settings.fileExtension).\(settings.fileExtension).\(settings.fileExtension)"
            let rawURL = finalURL.deletingLastPathComponent().appendingPathComponent(rawName)
            guard let rawMarker = createReservationMarker(for: rawURL) else {
                failRecordingStart("Unable to reserve a temporary recording file.".local, token: token)
                return
            }
            writerURL = rawURL
            writerReservationURL = rawMarker
        } else {
            writerURL = finalURL
            writerReservationURL = outputReservationURL
        }
        guard let writerURL else {
            failRecordingStart("Unable to prepare the recording file.".local, token: token)
            return
        }

        do {
            let writer = try AVAssetWriter(outputURL: writerURL, fileType: settings.fileType)
            writer.shouldOptimizeForNetworkUse = true
            let codecs: [AVVideoCodecType] = settings.requestedCodec == .h264 ? [.h264, .hevc] : [.hevc, .h264]
            var selectedCodec: AVVideoCodecType?
            var selectedVideoSettings: [String: Any]?
            for codec in codecs {
                let videoSettings = makeVideoSettings(codec: codec, size: outputSize, frameRate: settings.frameRate)
                if writer.canApply(outputSettings: videoSettings, forMediaType: .video) {
                    selectedCodec = codec
                    selectedVideoSettings = videoSettings
                    break
                }
            }
            guard let selectedCodec, let selectedVideoSettings else {
                throw NSError(domain: "WebcamScreenRecorder", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No supported H.264 or HEVC video encoder is available.".local
                ])
            }
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: selectedVideoSettings)
            video.expectsMediaDataInRealTime = true
            guard writer.canAdd(video) else {
                throw NSError(domain: "WebcamScreenRecorder", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "The video input cannot be added to the recording writer.".local
                ])
            }
            writer.add(video)
            var pixelAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
            pixelAttributes[kCVPixelBufferMetalCompatibilityKey as String] = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: video,
                sourcePixelBufferAttributes: pixelAttributes
            )
            var microphone: AVAssetWriterInput?
            var system: AVAssetWriterInput?
            if settings.hasMicrophone {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.aacOutputSettings)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else {
                    throw NSError(domain: "WebcamScreenRecorder", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "The microphone input cannot be added to the recording writer.".local
                    ])
                }
                writer.add(input)
                microphone = input
            }
            if settings.hasSystemAudio {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.aacOutputSettings)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else {
                    throw NSError(domain: "WebcamScreenRecorder", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: "The system audio input cannot be added to the recording writer.".local
                    ])
                }
                writer.add(input)
                system = input
            }
            self.writer = writer
            videoInput = video
            microphoneInput = microphone
            systemAudioInput = system
            pixelBufferAdaptor = adaptor
            let actualCodec = selectedCodec == .h264 ? "H.264" : "HEVC"
            let fileFormat = settings.fileType == .mov ? "MOV" : "MP4"
            publishFormat(
                String(format: "Webcam + Screen output: %d × %d at %d fps (%@, %@)".local, outputSize.width, outputSize.height, settings.frameRate, fileFormat, actualCodec),
                token: token
            )
            DispatchQueue.main.sync {
                SCContext.screen = selectedSCDisplay
                SCContext.filePath = finalURL.path
                SCContext.streamType = .screen
                SCContext.autoStop = settings.autoStopMinutes
                SCContext.isPaused = false
                SCContext.timePassed = 0
                SCContext.startTime = nil
                PopoverState.shared.isPaused = false
                updateStatusBar()
                self.sharedRecordingStateClaimed = true
            }
            startWriterStartWatchdog(token: token)
        } catch {
            failRecordingStart(String(format: "Unable to prepare the recording writer: %@".local, error.localizedDescription), token: token)
        }
    }

    private static let aacOutputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 192000
    ]

    private func makeVideoSettings(codec: AVVideoCodecType, size: WebcamScreenOutputSize, frameRate: Int) -> [String: Any] {
        let bitrate = min(18_000_000, max(2_000_000, size.width * size.height * frameRate / 2))
        let profile: String = codec == .h264 ? AVVideoProfileLevelH264HighAutoLevel : (kVTProfileLevel_HEVC_Main_AutoLevel as String)
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: profile,
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]
    }

    private func startWriterStartWatchdog(token: UUID) {
        cancelTimer(&writerStartTimer)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        writerStartTimer = timer
        timer.schedule(deadline: .now() + 10)
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == token,
                  self.backendState == .starting, !self.writerStarted else { return }
            self.handleCaptureFailure("Timed out waiting for a valid screen and camera frame.".local)
        }
        timer.resume()
    }

    private func renderTick(token: UUID) {
        guard generation == token, backendState != .idle, backendState != .finishing else { return }
        let now = hostNow()
        if let latestCamera = cameraFrames.values.last,
           now - latestCamera.hostTime > 1.0 {
            handleCaptureFailure("Camera frames stopped arriving; recording has stopped.".local)
            return
        }
        guard let screen = latestCompleteScreen,
              let screenHostTime = latestCompleteScreenHostTime,
              screenHostTime <= now,
              let cameraFrame = cameraFrames.latest(notAfter: now),
              now - cameraFrame.hostTime <= 1.0,
              let composite = compositor.compositeImage(
                  screen: screen,
                  camera: cameraFrame.value,
                  layout: layout,
                  outputSize: CGSize(width: CGFloat(outputSize.width), height: CGFloat(outputSize.height))
              ) else {
            return
        }

        if backendState == .preparing {
            backendState = .previewing
            cancelTimer(&startupTimer)
            publishState(.previewing, token: token)
        }
        publishCompositePreview(composite, at: now, token: token)

        guard backendState == .starting || backendState == .recording else { return }
        guard let writer, let videoInput, let adaptor = pixelBufferAdaptor,
              writer.status == .unknown || writer.status == .writing else {
            handleCaptureFailure(writer?.error?.localizedDescription ?? "The recording writer is unavailable.".local)
            return
        }
        if !writerStarted {
            guard backendState == .starting, let outputURL = writerURL else { return }
            guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                handleCaptureFailure("The recording output file already exists.".local)
                return
            }
            let didStart = writer.startWriting()
            writerOutputOwned = didStart
            guard didStart, writer.status == .writing else {
                handleCaptureFailure(writer.error?.localizedDescription ?? "Unable to start the recording writer.".local)
                return
            }
            writer.startSession(atSourceTime: .zero)
            writerStarted = true
            cancelTimer(&writerStartTimer)
            timeline.start(at: now)
            effectiveDuration = 0
            lastDurationPublishHostTime = 0
            if recordingSettings?.preventSleep == true {
                SleepPreventer.shared.preventSleep(reason: "Webcam and screen recording in progress")
                sleepAssertionHeld = true
            }
            backendState = .recording
            publishState(.recording, token: token)
            DispatchQueue.main.sync {
                SCContext.startTime = Date.now
                SCContext.isPaused = false
                SCContext.timePassed = 0
                PopoverState.shared.isPaused = false
            }
        }
        if videoBackpressure.timedOut(isReady: videoInput.isReadyForMoreMediaData, at: now) {
            handleCaptureFailure("The recording writer could not keep up with incoming media.".local)
            return
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        if let input = microphoneInput,
           microphoneBackpressure.timedOut(isReady: input.isReadyForMoreMediaData, at: now) {
            handleCaptureFailure("The recording writer could not keep up with incoming media.".local)
            return
        }
        if let input = systemAudioInput,
           systemAudioBackpressure.timedOut(isReady: input.isReadyForMoreMediaData, at: now) {
            handleCaptureFailure("The recording writer could not keep up with incoming media.".local)
            return
        }
        guard let elapsed = timeline.elapsed(at: now), lastVideoPTS.accept(elapsed) else { return }
        var pixelBuffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else {
            handleCaptureFailure("Unable to allocate a video frame.".local)
            return
        }
        compositor.render(composite, into: pixelBuffer, outputSize: CGSize(width: CGFloat(outputSize.width), height: CGFloat(outputSize.height)))
        let pts = CMTime(seconds: elapsed, preferredTimescale: 60_000)
        guard adaptor.append(pixelBuffer, withPresentationTime: pts) else {
            handleCaptureFailure(writer.error?.localizedDescription ?? "Unable to append a video frame.".local)
            return
        }

        if now - lastDurationPublishHostTime >= 0.25 {
            lastDurationPublishHostTime = now
            let duration = timeline.elapsed(at: now) ?? 0
            effectiveDuration = duration
            publishDuration(duration, token: token)
            DispatchQueue.main.async {
                guard self.publishedGeneration == token else { return }
                SCContext.timePassed = duration
            }
            if let autoStopMinutes = recordingSettings?.autoStopMinutes,
               autoStopMinutes > 0, duration >= Double(autoStopMinutes) * 60 {
                beginFinish(token: token, cancellation: false)
            }
        }
    }

    private func publishCompositePreview(_ image: CIImage, at hostTime: TimeInterval, token: UUID) {
        guard !previewPublishPending,
              hostTime - lastPreviewHostTime >= 0.2,
              let preview = compositor.makeImage(
                  image,
                  outputSize: CGSize(width: CGFloat(outputSize.width), height: CGFloat(outputSize.height))
              ) else { return }
        lastPreviewHostTime = hostTime
        lastCompositeImage = preview
        previewPublishPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.publishedGeneration == token {
                self.previewImage = preview
            }
            self.queue.async { self.previewPublishPending = false }
        }
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer, sourceClock: CMClock?, input: AVAssetWriterInput?, isMicrophone: Bool) {
        guard backendState == .recording, writerStarted,
              let writer, writer.status == .writing,
              let sourceClock, let input else { return }
        let now = hostNow()
        let backpressureTimedOut = isMicrophone
            ? microphoneBackpressure.timedOut(isReady: input.isReadyForMoreMediaData, at: now)
            : systemAudioBackpressure.timedOut(isReady: input.isReadyForMoreMediaData, at: now)
        if backpressureTimedOut {
            handleCaptureFailure("The recording writer could not keep up with incoming media.".local)
            return
        }
        guard input.isReadyForMoreMediaData,
              let (adjusted, outputPTS) = adjustedAudioSample(sampleBuffer, sourceClock: sourceClock),
              (isMicrophone ? lastMicrophonePTS : lastSystemAudioPTS).last.map({ outputPTS > $0 }) ?? true else { return }
        if isMicrophone {
            guard lastMicrophonePTS.accept(outputPTS) else { return }
        } else {
            guard lastSystemAudioPTS.accept(outputPTS) else { return }
        }
        guard input.append(adjusted) else {
            handleCaptureFailure(writer.error?.localizedDescription ?? "Unable to append an audio sample.".local)
            return
        }
    }

    private func adjustedAudioSample(_ sampleBuffer: CMSampleBuffer, sourceClock: CMClock) -> (CMSampleBuffer, TimeInterval)? {
        guard let origin = timeline.origin else { return nil }
        var entriesNeeded: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &entriesNeeded
        ) == noErr, entriesNeeded > 0 else { return nil }
        var timings = Array(
            repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
            count: Int(entriesNeeded)
        )
        let readStatus = timings.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: entriesNeeded,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &entriesNeeded
            )
        }
        guard readStatus == noErr else { return nil }
        let sampleCount = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        let bufferDurationSeconds = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
        let validBufferDuration = bufferDurationSeconds.isFinite && bufferDurationSeconds > 0
            ? bufferDurationSeconds
            : 0
        func pauseOverlapDuration(for timing: CMSampleTimingInfo) -> TimeInterval {
            let sampleDuration = CMTimeGetSeconds(timing.duration)
            if timings.count == 1, sampleCount > 1, validBufferDuration > 0 {
                return validBufferDuration
            }
            return sampleDuration.isFinite && sampleDuration > 0 ? sampleDuration : validBufferDuration
        }
        var outputPTS: TimeInterval?
        for index in timings.indices {
            if timings[index].presentationTimeStamp.isValid {
                let host = CMTimeGetSeconds(CMSyncConvertTime(
                    timings[index].presentationTimeStamp,
                    from: sourceClock,
                    to: CMClockGetHostTimeClock()
                ))
                guard host.isFinite, host >= origin,
                      !timeline.overlapsPause(from: host, duration: pauseOverlapDuration(for: timings[index])),
                      let elapsed = timeline.elapsed(at: host) else { return nil }
                timings[index].presentationTimeStamp = CMTime(seconds: elapsed, preferredTimescale: 60_000)
                if outputPTS == nil { outputPTS = elapsed }
            }
            if timings[index].decodeTimeStamp.isValid {
                let host = CMTimeGetSeconds(CMSyncConvertTime(
                    timings[index].decodeTimeStamp,
                    from: sourceClock,
                    to: CMClockGetHostTimeClock()
                ))
                guard host.isFinite, host >= origin,
                      !timeline.overlapsPause(from: host, duration: pauseOverlapDuration(for: timings[index])),
                      let elapsed = timeline.elapsed(at: host) else { return nil }
                timings[index].decodeTimeStamp = CMTime(seconds: elapsed, preferredTimescale: 60_000)
            }
        }
        guard let outputPTS, outputPTS.isFinite else { return nil }
        var adjusted: CMSampleBuffer?
        let status = timings.withUnsafeBufferPointer { buffer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: CMItemCount(buffer.count),
                sampleTimingArray: buffer.baseAddress!,
                sampleBufferOut: &adjusted
            )
        }
        guard status == noErr, let adjusted else { return nil }
        return (adjusted, outputPTS)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard DispatchQueue.getSpecific(key: queueKey) != nil else {
            queue.async { self.processCameraOutput(output, sampleBuffer: sampleBuffer, token: self.generation) }
            return
        }
        processCameraOutput(output, sampleBuffer: sampleBuffer, token: generation)
    }

    private func processCameraOutput(_ output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, token: UUID) {
        guard generation == token, backendState != .idle, backendState != .finishing,
              sampleBuffer.isValid else { return }
        if output === videoOutput {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let cameraClock,
                  CMSampleBufferGetPresentationTimeStamp(sampleBuffer).isValid else { return }
            let hostPTS = CMSyncConvertTime(
                CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                from: cameraClock,
                to: CMClockGetHostTimeClock()
            )
            let hostTime = CMTimeGetSeconds(hostPTS)
            guard hostTime.isFinite else { return }
            cameraFrames.append(imageBuffer, at: hostTime)
        } else if output === microphoneOutput {
            appendAudioSample(sampleBuffer, sourceClock: cameraClock, input: microphoneInput, isMicrophone: true)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard DispatchQueue.getSpecific(key: queueKey) != nil else {
            queue.async { self.processScreenOutput(stream, sampleBuffer: sampleBuffer, outputType: outputType) }
            return
        }
        processScreenOutput(stream, sampleBuffer: sampleBuffer, outputType: outputType)
    }

    private func processScreenOutput(_ stream: SCStream, sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard screenStream === stream, !screenStopInFlight, backendState != .idle, backendState != .finishing else { return }
        switch outputType {
        case .screen:
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first,
                  let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue) else { return }
            switch status {
            case .complete:
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                      CMSampleBufferGetPresentationTimeStamp(sampleBuffer).isValid else { return }
                guard let screenClock else {
                    pendingCompleteScreenFrame.holdComplete(sampleBuffer)
                    return
                }
                let hostPTS = CMSyncConvertTime(
                    CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                    from: screenClock,
                    to: CMClockGetHostTimeClock()
                )
                let hostTime = CMTimeGetSeconds(hostPTS)
                guard hostTime.isFinite else { return }
                latestCompleteScreen = imageBuffer
                latestCompleteScreenHostTime = hostTime
            case .idle:
                pendingCompleteScreenFrame.ignoreIdle()
            case .blank:
                handleCaptureFailure("The screen is blank; Webcam + Screen recording has stopped.".local)
            case .suspended:
                handleCaptureFailure("The screen capture was suspended; Webcam + Screen recording has stopped.".local)
            case .started:
                break
            case .stopped:
                handleCaptureFailure("The screen capture stopped unexpectedly.".local)
            @unknown default:
                break
            }
        case .audio:
            appendAudioSample(sampleBuffer, sourceClock: screenClock, input: systemAudioInput, isMicrophone: false)
#if compiler(>=6.0)
        case .microphone:
            break
#endif
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async {
            guard self.screenStream === stream, !self.screenStopInFlight, self.backendState != .finishing else { return }
            self.handleCaptureFailure(String(format: "Screen capture failed: %@".local, error.localizedDescription))
        }
    }

    @available(macOS 14.0, *)
    func outputVideoEffectDidStart(for stream: SCStream) {
        queue.async {
            guard self.screenStream === stream else { return }
            self.handleCaptureFailure("Presenter Overlay is enabled. Turn it off to use Webcam + Screen.".local)
        }
    }

    private func handleCaptureFailure(_ message: String) {
        guard backendState != .idle, backendState != .finishing else { return }
        runtimeFailureMessage = message
        publishError(message, token: generation)
        switch backendState {
        case .preparing, .previewing, .countdown:
            beginFinish(token: generation, cancellation: true)
        case .starting, .recording, .paused:
            beginFinish(token: generation, cancellation: !writerStarted)
        case .idle, .finishing:
            break
        }
    }

    private func failPreparation(_ message: String, token: UUID) {
        guard generation == token, backendState != .finishing else { return }
        publishError(message, token: token)
        runtimeFailureMessage = message
        beginFinish(token: token, cancellation: true)
    }

    private func failRecordingStart(_ message: String, token: UUID) {
        guard generation == token else { return }
        publishError(message, token: token)
        cleanupWriterFiles(removeOutput: false)
        if sharedRecordingStateClaimed {
            DispatchQueue.main.sync {
                SCContext.streamType = nil
                SCContext.screen = nil
                SCContext.startTime = nil
                SCContext.isPaused = false
                SCContext.autoStop = 0
                PopoverState.shared.isPaused = false
                updateStatusBar()
            }
            sharedRecordingStateClaimed = false
        }
        recordingSettings = nil
        recordingURL = nil
        writerURL = nil
        writer = nil
        videoInput = nil
        microphoneInput = nil
        systemAudioInput = nil
        pixelBufferAdaptor = nil
        backendState = .previewing
        publishState(.previewing, token: token)
    }

    private func beginFinish(token: UUID, cancellation: Bool) {
        guard generation == token, backendState != .finishing, backendState != .idle else { return }
        cancelTimer(&countdownTimer)
        cancelTimer(&startupTimer)
        cancelTimer(&writerStartTimer)
        cancelTimer(&frameTimer)
        countdownValue = 0
        publishCountdown(0, token: token)
        backendState = .finishing
        publishState(.finishing, token: token)
        let finishDuration = timeline.elapsed(at: hostNow()) ?? effectiveDuration
        effectiveDuration = finishDuration
        publishDuration(finishDuration, token: token)
        captureFinishDone = false
        writerFinishDone = false
        finishResult = nil
        remuxResult = nil
        remuxStarted = false

        stopCaptureGraph { [weak self] in
            guard let self, self.generation == token else { return }
            self.captureFinishDone = true
            self.tryCompleteFinish(token: token, cancellation: cancellation, duration: effectiveDuration)
        }

        guard writerStarted, let writer, !writerFinishRequested else {
            writerFinishDone = true
            finishResult = WriterFinishResult(success: false, error: nil)
            tryCompleteFinish(token: token, cancellation: cancellation, duration: effectiveDuration)
            return
        }
        writerFinishRequested = true
        videoInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        writer.finishWriting {
            self.queue.async {
                guard self.generation == token, self.backendState == .finishing else { return }
                let attributes = try? FileManager.default.attributesOfItem(atPath: self.writerURL?.path ?? "")
                let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                let success = writer.status == .completed && fileSize > 0
                let error = success ? nil : writer.error?.localizedDescription ?? "Recording did not produce a playable video.".local
                self.writerFinishDone = true
                self.finishResult = WriterFinishResult(success: success, error: error)
                self.tryCompleteFinish(token: token, cancellation: cancellation, duration: self.effectiveDuration)
            }
        }
    }

    private func tryCompleteFinish(token: UUID, cancellation: Bool, duration: TimeInterval) {
        guard generation == token, backendState == .finishing,
              captureFinishDone, writerFinishDone,
              let writerResult = finishResult else { return }
        if writerResult.success,
           recordingSettings?.remuxAudio == true,
           recordingSettings?.hasMicrophone == true,
           recordingSettings?.hasSystemAudio == true,
           !remuxStarted {
            remuxStarted = true
            startAudioRemux(token: token, duration: duration)
            return
        }
        if let remuxResult {
            completeFinish(token: token, cancellation: cancellation, duration: duration, writerResult: writerResult, remuxResult: remuxResult)
            return
        }
        if remuxStarted { return }
        completeFinish(
            token: token,
            cancellation: cancellation,
            duration: duration,
            writerResult: writerResult,
            remuxResult: nil
        )
    }

    private func startAudioRemux(token: UUID, duration: TimeInterval) {
        guard let settings = recordingSettings,
              let sourceURL = writerURL, let outputURL = recordingURL else {
            remuxResult = RemuxResult(outputURL: writerURL ?? recordingURL ?? URL(fileURLWithPath: NSTemporaryDirectory()), warning: "Audio tracks could not be mixed.".local)
            tryCompleteFinish(token: token, cancellation: false, duration: duration)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let sourceAsset = AVURLAsset(url: sourceURL)
            let sourceVideoTracks = sourceAsset.tracks(withMediaType: .video)
            let sourceAudioTracks = sourceAsset.tracks(withMediaType: .audio)
            guard let sourceVideo = sourceVideoTracks.first, sourceAudioTracks.count >= 2 else {
                self.finishRemuxFailure(
                    sourceURL: sourceURL,
                    token: token,
                    duration: duration,
                    error: "The original recording does not contain both audio tracks.".local
                )
                return
            }

            let audioComposition = AVMutableComposition()
            var audioMixParameters = [AVMutableAudioMixInputParameters]()
            for sourceAudio in sourceAudioTracks {
                guard let destinationAudio = audioComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    self.finishRemuxFailure(sourceURL: sourceURL, token: token, duration: duration, error: "Unable to create an audio composition.".local)
                    return
                }
                do {
                    try destinationAudio.insertTimeRange(sourceAudio.timeRange, of: sourceAudio, at: sourceAudio.timeRange.start)
                } catch {
                    self.finishRemuxFailure(sourceURL: sourceURL, token: token, duration: duration, error: error.localizedDescription)
                    return
                }
                let parameters = AVMutableAudioMixInputParameters(track: destinationAudio)
                parameters.trackID = destinationAudio.trackID
                audioMixParameters.append(parameters)
            }

            guard let audioExport = AVAssetExportSession(asset: audioComposition, presetName: AVAssetExportPresetAppleM4A),
                  audioExport.supportedFileTypes.contains(.m4a) else {
                self.finishRemuxFailure(sourceURL: sourceURL, token: token, duration: duration, error: "Unable to create a compatible audio mix export.".local)
                return
            }
            guard let audioTemporary = self.reserveTemporaryURL(
                near: outputURL,
                purpose: "audio-mix",
                fileExtension: "m4a"
            ) else {
                self.finishRemuxFailure(sourceURL: sourceURL, token: token, duration: duration, error: "Unable to reserve a temporary mix file.".local)
                return
            }
            audioExport.outputURL = audioTemporary.url
            audioExport.outputFileType = .m4a
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            audioExport.audioMix = audioMix
            audioExport.shouldOptimizeForNetworkUse = true

            audioExport.exportAsynchronously {
                guard audioExport.status == .completed,
                      FileManager.default.fileExists(atPath: audioTemporary.url.path) else {
                    self.finishRemuxFailure(
                        sourceURL: sourceURL,
                        token: token,
                        duration: duration,
                        error: audioExport.error?.localizedDescription ?? "Audio mix export failed.".local,
                        cleanupURLs: [audioTemporary.url],
                        cleanupMarkers: [audioTemporary.marker]
                    )
                    return
                }

                let mixedAudioAsset = AVURLAsset(url: audioTemporary.url)
                let mixedAudioTracks = mixedAudioAsset.tracks(withMediaType: .audio)
                guard mixedAudioTracks.count == 1, let mixedAudioSource = mixedAudioTracks.first else {
                    self.finishRemuxFailure(
                        sourceURL: sourceURL,
                        token: token,
                        duration: duration,
                        error: "The mixed audio export did not produce exactly one audio track.".local,
                        cleanupURLs: [audioTemporary.url],
                        cleanupMarkers: [audioTemporary.marker]
                    )
                    return
                }

                let muxComposition = AVMutableComposition()
                guard let muxVideoTrack = muxComposition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ), let muxAudioTrack = muxComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    self.finishRemuxFailure(
                        sourceURL: sourceURL,
                        token: token,
                        duration: duration,
                        error: "Unable to create a final video and audio composition.".local,
                        cleanupURLs: [audioTemporary.url],
                        cleanupMarkers: [audioTemporary.marker]
                    )
                    return
                }
                do {
                    try muxVideoTrack.insertTimeRange(sourceVideo.timeRange, of: sourceVideo, at: sourceVideo.timeRange.start)
                    try muxAudioTrack.insertTimeRange(mixedAudioSource.timeRange, of: mixedAudioSource, at: mixedAudioSource.timeRange.start)
                } catch {
                    self.finishRemuxFailure(
                        sourceURL: sourceURL,
                        token: token,
                        duration: duration,
                        error: error.localizedDescription,
                        cleanupURLs: [audioTemporary.url],
                        cleanupMarkers: [audioTemporary.marker]
                    )
                    return
                }
                guard let muxExport = AVAssetExportSession(asset: muxComposition, presetName: AVAssetExportPresetPassthrough),
                      muxExport.supportedFileTypes.contains(settings.fileType) else {
                    self.finishRemuxFailure(
                        sourceURL: sourceURL,
                        token: token,
                        duration: duration,
                        error: "Unable to create a codec-preserving final export.".local,
                        cleanupURLs: [audioTemporary.url],
                        cleanupMarkers: [audioTemporary.marker]
                    )
                    return
                }
                guard let finalTemporary = self.reserveTemporaryURL(
                    near: outputURL,
                    purpose: "remux",
                    fileExtension: settings.fileExtension
                ) else {
                    self.finishRemuxFailure(
                        sourceURL: sourceURL,
                        token: token,
                        duration: duration,
                        error: "Unable to reserve a temporary remux file.".local,
                        cleanupURLs: [audioTemporary.url],
                        cleanupMarkers: [audioTemporary.marker]
                    )
                    return
                }
                muxExport.outputURL = finalTemporary.url
                muxExport.outputFileType = settings.fileType
                muxExport.shouldOptimizeForNetworkUse = true
                muxExport.exportAsynchronously {
                    // AVAssetTrack.asset is weak; retain both assets until the asynchronous mux finishes.
                    defer { withExtendedLifetime((sourceAsset, mixedAudioAsset)) {} }
                    var succeeded = muxExport.status == .completed
                        && FileManager.default.fileExists(atPath: finalTemporary.url.path)
                    if succeeded {
                        do {
                            guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                                throw NSError(domain: "WebcamScreenRecorder", code: 5, userInfo: [
                                    NSLocalizedDescriptionKey: "The final recording file already exists.".local
                                ])
                            }
                            try FileManager.default.moveItem(at: finalTemporary.url, to: outputURL)
                        } catch {
                            succeeded = false
                        }
                    }
                    if !succeeded { try? FileManager.default.removeItem(at: finalTemporary.url) }
                    try? FileManager.default.removeItem(at: audioTemporary.url)
                    try? FileManager.default.removeItem(at: audioTemporary.marker)
                    try? FileManager.default.removeItem(at: finalTemporary.marker)
                    let warning = succeeded ? nil : String(
                        format: "Audio tracks could not be mixed. The original multi-track recording was preserved at: %@".local,
                        sourceURL.path
                    ) + " " + (muxExport.error?.localizedDescription ?? "Final remux export failed.".local)
                    self.queue.async {
                        guard self.generation == token else { return }
                        self.remuxResult = RemuxResult(outputURL: succeeded ? outputURL : sourceURL, warning: warning)
                        self.tryCompleteFinish(token: token, cancellation: false, duration: duration)
                    }
                }
            }
        }
    }

    private func finishRemuxFailure(
        sourceURL: URL,
        token: UUID,
        duration: TimeInterval,
        error: String,
        cleanupURLs: [URL] = [],
        cleanupMarkers: [URL] = []
    ) {
        cleanupURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        cleanupMarkers.forEach { try? FileManager.default.removeItem(at: $0) }
        let warning = String(
            format: "Audio tracks could not be mixed. The original multi-track recording was preserved at: %@".local,
            sourceURL.path
        ) + " " + error
        queue.async {
            guard self.generation == token else { return }
            self.remuxResult = RemuxResult(outputURL: sourceURL, warning: warning)
            self.tryCompleteFinish(token: token, cancellation: false, duration: duration)
        }
    }

    private func completeFinish(
        token: UUID,
        cancellation: Bool,
        duration: TimeInterval,
        writerResult: WriterFinishResult,
        remuxResult: RemuxResult?
    ) {
        guard generation == token else { return }
        let settings = recordingSettings
        let outputURL = remuxResult?.outputURL ?? (writerResult.success ? writerURL : nil)
        let success = writerResult.success && outputURL != nil
        if let outputURL, outputURL != writerURL {
            try? FileManager.default.removeItem(at: writerURL ?? outputURL)
        }
        cleanupReservationMarkers()
        if !success { cleanupWriterFiles(removeOutput: true) }
        if sleepAssertionHeld {
            SleepPreventer.shared.allowSleep()
            sleepAssertionHeld = false
        }

        let terminalGeneration = UUID()
        generation = terminalGeneration
        backendState = .idle
        recordingSettings = nil
        recordingURL = nil
        writerURL = nil
        writer = nil
        videoInput = nil
        microphoneInput = nil
        systemAudioInput = nil
        pixelBufferAdaptor = nil
        writerStarted = false
        writerOutputOwned = false
        writerFinishRequested = false
        timeline = WebcamScreenTimeline()
        cameraFrames.removeAll()
        latestCompleteScreen = nil
        screenClock = nil
        cameraClock = nil
        let thumbnail = lastCompositeImage
        lastCompositeImage = nil
        let message = runtimeFailureMessage ?? writerResult.error
        runtimeFailureMessage = nil
        let finalOutput = outputURL

        DispatchQueue.main.sync {
            if self.sharedRecordingStateClaimed {
                SCContext.streamType = nil
                SCContext.startTime = nil
                SCContext.isPaused = false
                SCContext.autoStop = 0
                SCContext.timePassed = duration
                PopoverState.shared.isPaused = false
                SCContext.screen = nil
                if success, let finalOutput { SCContext.filePath = finalOutput.path }
                if success, let finalOutput {
                    if settings?.showPreview == true, let thumbnail {
                        SCContext.showPreview(path: finalOutput.path, image: thumbnail)
                    } else {
                        SCContext.showNotification(
                            title: "Recording Completed".local,
                            body: String(format: "File saved to: %@".local, finalOutput.path),
                            id: "quickrecorder.webcam-screen.completed.\(UUID().uuidString)"
                        )
                    }
                    if let warning = remuxResult?.warning {
                        SCContext.showNotification(
                            title: "Audio tracks remain separate".local,
                            body: warning,
                            id: "quickrecorder.webcam-screen.remux.\(UUID().uuidString)"
                        )
                    }
                    if let message, !cancellation {
                        SCContext.showNotification(
                            title: "Recording stopped unexpectedly".local,
                            body: message,
                            id: "quickrecorder.webcam-screen.interrupted.\(UUID().uuidString)"
                        )
                    }
                    if settings?.trimAfterRecord == true {
                        AppDelegate.shared.createNewWindow(
                            view: VideoTrimmerView(videoURL: finalOutput),
                            title: finalOutput.lastPathComponent,
                            only: false
                        )
                    }
                } else if !cancellation {
                    SCContext.showNotification(
                        title: "Failed to save file".local,
                        body: message ?? "Recording did not produce a playable video.".local,
                        id: "quickrecorder.webcam-screen.error.\(UUID().uuidString)"
                    )
                }
                updateStatusBar()
                self.sharedRecordingStateClaimed = false
            }
            self.publishedGeneration = terminalGeneration
            self.errorMessage = cancellation ? self.errorMessage : message ?? remuxResult?.warning
            self.previewImage = nil
            self.actualFormatDescription = ""
            self.countdownRemaining = 0
            self.recordedDuration = duration
            self.isPaused = false
            self.isBusy = false
            self.state = .idle
        }
    }


    private func stopCaptureGraph(completion: @escaping () -> Void) {
        cancelTimer(&frameTimer)
        cancelTimer(&startupTimer)
        pendingCompleteScreenFrame.clear()
        screenClock = nil
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        sessionObservers.removeAll()
        if let session = cameraSession {
            if session.isRunning { session.stopRunning() }
            cameraSession = nil
            cameraDevice = nil
            microphoneDevice = nil
            videoOutput = nil
            microphoneOutput = nil
            cameraClock = nil
        }
        cameraFrames.removeAll()
        latestCompleteScreen = nil
        latestCompleteScreenHostTime = nil
        captureCleanupCompletions.append(completion)
        guard let stream = screenStream else {
            if !screenStartInFlight && !screenStopInFlight { drainCaptureCleanupCompletions() }
            return
        }
        if screenStartInFlight {
            stopAfterScreenStart = true
            return
        }
        startScreenStop(stream)
    }

    private func startScreenStop(_ stream: SCStream) {
        guard screenStream === stream, !screenStopInFlight else { return }
        screenStopInFlight = true
        stream.stopCapture { error in
            self.queue.async { self.screenStopCompleted(stream, error: error) }
        }
    }

    private func screenStopCompleted(_ stream: SCStream, error: Error?) {
        guard screenStream === stream else { return }
        screenStopInFlight = false
        screenStream = nil
        screenClock = nil
        if let error, backendState != .finishing {
            runtimeFailureMessage = String(format: "Unable to stop screen capture: %@".local, error.localizedDescription)
        }
        drainCaptureCleanupCompletions()
    }

    private func drainCaptureCleanupCompletions() {
        guard !screenStartInFlight, !screenStopInFlight, screenStream == nil else { return }
        let completions = captureCleanupCompletions
        captureCleanupCompletions.removeAll()
        completions.forEach { $0() }
    }


    private func reserveOutputURL(fileExtension: String) -> (url: URL, marker: URL)? {
        guard let directoryPath = UserDefaults.standard.string(forKey: "saveDirectory"),
              !directoryPath.isEmpty else { return nil }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue, FileManager.default.isWritableFile(atPath: directory.path) else { return nil }
        let name = URL(fileURLWithPath: SCContext.getFilePath()).lastPathComponent
        var suffix = 0
        while suffix < 10_000 {
            let suffixText = suffix == 0 ? "" : " (\(suffix))"
            let output = directory.appendingPathComponent(name + suffixText).appendingPathExtension(fileExtension)
            if !FileManager.default.fileExists(atPath: output.path),
               let marker = createReservationMarker(for: output) {
                return (output, marker)
            }
            suffix += 1
        }
        return nil
    }

    private func createReservationMarker(for url: URL) -> URL? {
        let marker = url.appendingPathExtension("quickrecorder-reserve")
        let descriptor = Darwin.open(marker.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        Darwin.close(descriptor)
        return marker
    }

    private func reserveTemporaryURL(
        near outputURL: URL,
        purpose: String,
        fileExtension: String
    ) -> (url: URL, marker: URL)? {
        let directory = outputURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let name = "\(outputURL.deletingPathExtension().lastPathComponent)-\(purpose)-\(UUID().uuidString).\(fileExtension)"
            let candidate = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: candidate.path),
                  let marker = createReservationMarker(for: candidate) else { continue }
            if FileManager.default.fileExists(atPath: candidate.path) {
                try? FileManager.default.removeItem(at: marker)
                continue
            }
            return (candidate, marker)
        }
        return nil
    }

    private func cleanupReservationMarkers() {
        if let outputReservationURL { try? FileManager.default.removeItem(at: outputReservationURL) }
        if let writerReservationURL, writerReservationURL != outputReservationURL {
            try? FileManager.default.removeItem(at: writerReservationURL)
        }
        outputReservationURL = nil
        writerReservationURL = nil
    }

    private func cleanupWriterFiles(removeOutput: Bool) {
        cleanupReservationMarkers()
        if removeOutput, writerOutputOwned, let writerURL,
           FileManager.default.fileExists(atPath: writerURL.path) {
            try? FileManager.default.removeItem(at: writerURL)
        }
        writerOutputOwned = false
    }

    private func hostNow() -> TimeInterval {
        CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
    }

    private func publishState(_ value: State, token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.publishedGeneration == token else { return }
            self.state = value
            self.isBusy = value != .idle
            self.isPaused = value == .paused
        }
    }

    private func publishError(_ value: String?, token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.publishedGeneration == token else { return }
            self.errorMessage = value
        }
    }

    private func publishFormat(_ value: String, token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.publishedGeneration == token else { return }
            self.actualFormatDescription = value
        }
    }

    private func publishDuration(_ value: TimeInterval, token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.publishedGeneration == token else { return }
            self.recordedDuration = max(0, value)
        }
    }

    private func publishCountdown(_ value: Int, token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.publishedGeneration == token else { return }
            self.countdownRemaining = value
        }
    }

    private func publishSharedPauseState(_ paused: Bool, duration: TimeInterval, token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.publishedGeneration == token else { return }
            SCContext.isPaused = paused
            SCContext.timePassed = duration
            SCContext.startTime = paused ? nil : Date.now.addingTimeInterval(-duration)
            PopoverState.shared.isPaused = paused
        }
    }

    private func cancelTimer(_ timer: inout DispatchSourceTimer?) {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
#if WEBCAM_SCREEN_TESTING
    func _testSetState(_ value: State) {
        let token = UUID()
        queue.sync {
            generation = token
            backendState = value
            timeline = WebcamScreenTimeline()
            if value == .recording || value == .paused {
                let now = hostNow()
                timeline.start(at: now)
                if value == .paused { timeline.pause(at: now) }
            }
            writerStarted = false
            writerOutputOwned = false
            writerFinishRequested = false
            writerFinishDone = false
            captureFinishDone = false
            screenStartInFlight = false
            screenStopInFlight = false
            stopAfterScreenStart = false
            screenStream = nil
            screenClock = nil
            pendingCompleteScreenFrame.clear()
            cameraClock = nil
            cameraSession = nil
            writer = nil
            videoInput = nil
            microphoneInput = nil
            systemAudioInput = nil
            pixelBufferAdaptor = nil
            writerURL = nil
            recordingURL = nil
            recordingSettings = nil
            outputReservationURL = nil
            writerReservationURL = nil
            captureCleanupCompletions.removeAll()
            cameraFrames.removeAll()
            latestCompleteScreen = nil
            latestCompleteScreenHostTime = nil
            sharedRecordingStateClaimed = false
            sleepAssertionHeld = false
            runtimeFailureMessage = nil
        }
        let update = {
            self.publishedGeneration = token
            self.state = value
            self.isBusy = value != .idle
            self.isPaused = value == .paused
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.sync(execute: update)
        }
    }

    func _testBackendState() -> State {
        queue.sync { backendState }
    }

    func _testLayout() -> WebcamScreenLayout {
        queue.sync { layout }
    }

    func _testFlushQueue() {
        queue.sync {}
    }

    func _testQueueBackendTransition(_ value: State) {
        queue.async {
            self.backendState = value
            self.countdownValue = value == .countdown ? 4 : 0
        }
    }

    func _testStartRemux(sourceURL: URL, outputURL: URL, fileExtension: String) {
        let token = UUID()
        queue.sync {
            generation = token
            backendState = .finishing
            recordingSettings = RecordingSettings(
                fileType: fileExtension == VideoFormat.mov.rawValue ? .mov : .mp4,
                fileExtension: fileExtension,
                requestedCodec: .h264,
                frameRate: 30,
                autoStopMinutes: 0,
                remuxAudio: true,
                showPreview: false,
                trimAfterRecord: false,
                preventSleep: false,
                hasMicrophone: true,
                hasSystemAudio: true
            )
            writerURL = sourceURL
            recordingURL = outputURL
            writer = nil
            writerStarted = true
            writerOutputOwned = false
            writerFinishRequested = true
            writerFinishDone = true
            captureFinishDone = true
            remuxStarted = true
            finishResult = WriterFinishResult(success: true, error: nil)
            remuxResult = nil
            effectiveDuration = 1
            outputReservationURL = nil
            writerReservationURL = nil
            sharedRecordingStateClaimed = false
            sleepAssertionHeld = false
            runtimeFailureMessage = nil
        }
        let update = {
            self.publishedGeneration = token
            self.state = .finishing
            self.isBusy = true
            self.isPaused = false
            self.errorMessage = nil
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.sync(execute: update)
        }
        queue.async {
            self.startAudioRemux(token: token, duration: 1)
        }
    }

    func _testSetTimeline(_ value: WebcamScreenTimeline) {
        queue.sync { timeline = value }
    }

    func _testAdjustedAudioSample(
        _ sampleBuffer: CMSampleBuffer,
        sourceClock: CMClock
    ) -> (CMSampleBuffer, TimeInterval)? {
        queue.sync { adjustedAudioSample(sampleBuffer, sourceClock: sourceClock) }
    }
#endif
}
// WEBCAM_SCREEN_BACKEND_END
