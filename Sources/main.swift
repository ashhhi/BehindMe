import AppKit
import AVFoundation
import CoreMedia
import CoreAudio
import Vision

enum AudioOutputSafety {
    struct OutputInfo {
        let deviceName: String
        let dataSourceName: String?

        var displayName: String {
            if let dataSourceName, !dataSourceName.isEmpty {
                return "\(deviceName) — \(dataSourceName)"
            }
            return deviceName
        }
    }

    static func currentOutput() -> OutputInfo? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        return OutputInfo(
            deviceName: stringProperty(
                objectID: deviceID,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal
            ) ?? "未知音频设备",
            dataSourceName: currentDataSourceName(deviceID: deviceID)
        )
    }

    static func isHeadphoneOutput(_ output: OutputInfo?) -> Bool {
        guard let output else { return false }

        let headphoneKeywords = [
            "headphone", "headset", "earphone", "earbuds", "earpods",
            "airpods", "air pods", "beats", "buds", "耳机"
        ]
        let speakerKeywords = [
            "speaker", "扬声器", "internal speakers", "built-in output"
        ]

        // Wired headphones can share the built-in device with the speakers,
        // so its active data source is the strongest signal.
        if let source = output.dataSourceName?.lowercased() {
            if headphoneKeywords.contains(where: source.contains) { return true }
            if speakerKeywords.contains(where: source.contains) { return false }
        }

        let device = output.deviceName.lowercased()
        if speakerKeywords.contains(where: device.contains) { return false }
        return headphoneKeywords.contains(where: device.contains)
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private static func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { valuePointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                valuePointer
            )
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func currentDataSourceName(deviceID: AudioDeviceID) -> String? {
        var sourceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &sourceAddress) else { return nil }

        var sourceID: UInt32 = 0
        var sourceIDSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &sourceAddress,
            0,
            nil,
            &sourceIDSize,
            &sourceID
        ) == noErr else { return nil }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &nameAddress) else { return nil }

        var sourceName: CFString?
        var lookupStatus: OSStatus = -1
        withUnsafeMutablePointer(to: &sourceID) { sourceIDPointer in
            withUnsafeMutablePointer(to: &sourceName) { sourceNamePointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(sourceIDPointer),
                    mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                    mOutputData: UnsafeMutableRawPointer(sourceNamePointer),
                    mOutputDataSize: UInt32(MemoryLayout<CFString?>.size)
                )
                var translationSize = UInt32(MemoryLayout<AudioValueTranslation>.size)
                lookupStatus = AudioObjectGetPropertyData(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &translationSize,
                    &translation
                )
            }
        }
        guard lookupStatus == noErr, let sourceName else { return nil }
        return sourceName as String
    }
}

final class CameraPreviewView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("尚未实现 init(coder:)")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    func attach(session: AVCaptureSession) {
        previewLayer.session = session
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

final class CameraWindowController: NSWindowController {
    let previewView: CameraPreviewView

    init(session: AVCaptureSession) {
        previewView = CameraPreviewView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BehindMe"
        window.contentView = previewView
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrameAutosaveName("BehindMeCameraWindow")
        window.center()

        super.init(window: window)
        previewView.attach(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("尚未实现 init(coder:)")
    }
}

final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    var onFaceCountChanged: ((Int) -> Void)?
    var onError: ((String) -> Void)?

    private let captureQueue = DispatchQueue(label: "BehindMe.capture")
    private let sampleQueue = DispatchQueue(label: "BehindMe.face-detection")
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var lastDetectionTime: CFAbsoluteTime = 0

    var faceDetectionEnabled = false

    func start() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.configured {
                    try self.configureSession()
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            } catch {
                DispatchQueue.main.async {
                    self.onError?(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .unspecified
        ) else {
            throw CameraError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)

        guard session.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }
        session.addOutput(output)

        configured = true
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard faceDetectionEnabled else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDetectionTime >= 0.35 else { return }
        lastDetectionTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .upMirrored,
            options: [:]
        )

        do {
            try handler.perform([request])
            let count = request.results?.count ?? 0
            DispatchQueue.main.async { [weak self] in
                self?.onFaceCountChanged?(count)
            }
        } catch {
            // A single dropped or invalid frame should not interrupt the camera session.
        }
    }
}

enum CameraError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "没有找到可用的摄像头。"
        case .cannotAddInput:
            return "无法读取摄像头输入。"
        case .cannotAddOutput:
            return "无法分析摄像头画面。"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let camera = CameraEngine()
    private var cameraWindowController: CameraWindowController?
    private var statusItem: NSStatusItem!

    private var showCameraItem: NSMenuItem!
    private var faceAlertItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private var headphonesOnlyItem: NSMenuItem!
    private var thresholdItems: [NSMenuItem] = []
    private var soundChoiceItems: [NSMenuItem] = []

    private var faceAlertEnabled = false
    private var soundEnabled = true
    private var threshold = 2
    private var selectedSoundName = UserDefaults.standard.string(forKey: "alertSoundName") ?? "Hero"
    private var headphonesOnly: Bool = {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "headphonesOnly") != nil else { return true }
        return defaults.bool(forKey: "headphonesOnly")
    }()
    private var activeSound: NSSound?
    private var wasAlerting = false
    private var lastSoundTime: CFAbsoluteTime = 0

    private let soundOptions: [(name: String, label: String)] = [
        ("Hero", "Hero（响亮）"),
        ("Sosumi", "Sosumi（经典）"),
        ("Basso", "Basso（低沉）"),
        ("Submarine", "Submarine（警示）"),
        ("Funk", "Funk（短促）"),
        ("Ping", "Ping（清脆）"),
        ("Glass", "Glass（明亮）")
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        camera.onFaceCountChanged = { [weak self] count in
            self?.handleFaceCount(count)
        }
        camera.onError = { [weak self] message in
            self?.showError(message)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◉"
        statusItem.button?.toolTip = "BehindMe"

        let menu = NSMenu()

        showCameraItem = NSMenuItem(
            title: "显示摄像头",
            action: #selector(toggleCameraWindow),
            keyEquivalent: ""
        )
        showCameraItem.target = self
        menu.addItem(showCameraItem)

        faceAlertItem = NSMenuItem(
            title: "开启人脸提醒",
            action: #selector(toggleFaceAlert),
            keyEquivalent: ""
        )
        faceAlertItem.target = self
        menu.addItem(faceAlertItem)

        let thresholdMenu = NSMenu()
        for value in 1...4 {
            let item = NSMenuItem(
                title: "检测到 \(value) 张脸",
                action: #selector(selectThreshold(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = value
            item.state = value == threshold ? .on : .off
            thresholdMenu.addItem(item)
            thresholdItems.append(item)
        }
        let thresholdRoot = NSMenuItem(title: "提醒阈值", action: nil, keyEquivalent: "")
        thresholdRoot.submenu = thresholdMenu
        menu.addItem(thresholdRoot)

        soundItem = NSMenuItem(
            title: "提醒时播放声音",
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.target = self
        soundItem.state = .on
        menu.addItem(soundItem)

        headphonesOnlyItem = NSMenuItem(
            title: "仅耳机播放",
            action: #selector(toggleHeadphonesOnly),
            keyEquivalent: ""
        )
        headphonesOnlyItem.target = self
        headphonesOnlyItem.state = headphonesOnly ? .on : .off
        menu.addItem(headphonesOnlyItem)

        let soundChoiceMenu = NSMenu()
        for option in soundOptions {
            let item = NSMenuItem(
                title: option.label,
                action: #selector(selectSound(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.name
            item.state = option.name == selectedSoundName ? .on : .off
            soundChoiceMenu.addItem(item)
            soundChoiceItems.append(item)
        }
        soundChoiceMenu.addItem(.separator())
        let previewSoundItem = NSMenuItem(
            title: "试听当前提示音",
            action: #selector(previewSound),
            keyEquivalent: ""
        )
        previewSoundItem.target = self
        soundChoiceMenu.addItem(previewSoundItem)

        let soundChoiceRoot = NSMenuItem(title: "选择提示音", action: nil, keyEquivalent: "")
        soundChoiceRoot.submenu = soundChoiceMenu
        menu.addItem(soundChoiceRoot)

        menu.addItem(.separator())

        let privacyItem = NSMenuItem(
            title: "隐私说明",
            action: #selector(showPrivacy),
            keyEquivalent: ""
        )
        privacyItem.target = self
        menu.addItem(privacyItem)

        let quitItem = NSMenuItem(
            title: "退出 BehindMe",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleCameraWindow() {
        if cameraWindowController?.window?.isVisible == true {
            cameraWindowController?.close()
            showCameraItem.title = "显示摄像头"
            return
        }

        withCameraPermission { [weak self] in
            guard let self else { return }
            if self.cameraWindowController == nil {
                self.cameraWindowController = CameraWindowController(session: self.camera.session)
            }
            self.camera.start()
            self.cameraWindowController?.showWindow(nil)
            self.cameraWindowController?.window?.orderFrontRegardless()
            self.showCameraItem.title = "隐藏摄像头"
        }
    }

    @objc private func toggleFaceAlert() {
        if faceAlertEnabled {
            faceAlertEnabled = false
            camera.faceDetectionEnabled = false
            faceAlertItem.state = .off
            faceAlertItem.title = "开启人脸提醒"
            statusItem.button?.title = "◉"
            wasAlerting = false
            return
        }

        withCameraPermission { [weak self] in
            guard let self else { return }
            self.faceAlertEnabled = true
            self.camera.faceDetectionEnabled = true
            self.faceAlertItem.state = .on
            self.faceAlertItem.title = "关闭人脸提醒"
            self.statusItem.button?.title = "🕶️"
            self.camera.start()
        }
    }

    @objc private func selectThreshold(_ sender: NSMenuItem) {
        threshold = sender.tag
        for item in thresholdItems {
            item.state = item.tag == threshold ? .on : .off
        }
        wasAlerting = false
    }

    @objc private func toggleSound() {
        soundEnabled.toggle()
        soundItem.state = soundEnabled ? .on : .off
    }

    @objc private func toggleHeadphonesOnly() {
        headphonesOnly.toggle()
        headphonesOnlyItem.state = headphonesOnly ? .on : .off
        UserDefaults.standard.set(headphonesOnly, forKey: "headphonesOnly")
    }

    @objc private func selectSound(_ sender: NSMenuItem) {
        guard let soundName = sender.representedObject as? String else { return }
        selectedSoundName = soundName
        UserDefaults.standard.set(soundName, forKey: "alertSoundName")
        for item in soundChoiceItems {
            item.state = (item.representedObject as? String) == soundName ? .on : .off
        }
        playSelectedSound()
    }

    @objc private func previewSound() {
        if !playSelectedSound() {
            showHeadphonesRequiredMessage()
        }
    }

    @objc private func showPrivacy() {
        let alert = NSAlert()
        alert.messageText = "隐私说明"
        alert.informativeText = "BehindMe 只在本机实时读取摄像头画面，用于预览和计算人脸数量。它不会录像、不会保存照片，也不会发送任何网络请求。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        camera.stop()
        NSApp.terminate(nil)
    }

    private func withCameraPermission(_ action: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            action()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        action()
                    } else {
                        self?.showCameraPermissionHelp()
                    }
                }
            }
        default:
            showCameraPermissionHelp()
        }
    }

    private func handleFaceCount(_ count: Int) {
        guard faceAlertEnabled else { return }

        let isAlerting = count >= threshold
        statusItem.button?.title = isAlerting ? "😱" : "🕶️"
        statusItem.button?.toolTip = isAlerting
            ? "检测到 \(count) 张脸"
            : "当前检测到 \(count) 张脸"

        if isAlerting && !wasAlerting && soundEnabled {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastSoundTime > 3 {
                if !playSelectedSound() {
                    statusItem.button?.toolTip = "检测到 \(count) 张脸；未检测到耳机，已保持静音"
                }
                lastSoundTime = now
            }
        }
        wasAlerting = isAlerting
    }

    @discardableResult
    private func playSelectedSound() -> Bool {
        activeSound?.stop()
        if headphonesOnly && !AudioOutputSafety.isHeadphoneOutput(AudioOutputSafety.currentOutput()) {
            return false
        }
        guard let sound = NSSound(named: NSSound.Name(selectedSoundName)) else {
            return false
        }
        sound.volume = 1.0
        activeSound = sound
        sound.play()
        return true
    }

    private func showHeadphonesRequiredMessage() {
        let outputDescription = AudioOutputSafety.currentOutput()?.displayName ?? "无法识别"
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "未检测到耳机"
        alert.informativeText = "当前输出：\(outputDescription)\n\n为了避免声音从扬声器播放，提示音已保持静音。连接耳机并将它设为系统输出后再试。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showCameraPermissionHelp() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要摄像头权限"
        alert.informativeText = "请前往“系统设置 → 隐私与安全性 → 摄像头”，允许 BehindMe 使用摄像头。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "摄像头无法启动"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
