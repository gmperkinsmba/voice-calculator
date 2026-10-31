import AppKit
import AVFoundation
import CoreGraphics
import ApplicationServices
import Speech

@MainActor
final class NativeSpeechDriver: SpeechCaptureDriver {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var partial: ((String) -> Void)?
    private var completion: ((Result<String, CaptureFailure>) -> Void)?
    private var latest = ""
    private var sessionGate = RecognitionSessionGate()

    func start(onPartial: @escaping (String) -> Void,
               onCompletion: @escaping (Result<String, CaptureFailure>) -> Void) throws {
        guard let recognizer else { throw CaptureFailure.speechRecognizerUnavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw CaptureFailure.onDeviceRecognitionUnavailable }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw CaptureFailure.recognition("Grant Speech Recognition and Microphone access in Settings.")
        }

        cleanup()
        let sessionID = sessionGate.begin()
        self.partial = onPartial
        self.completion = onCompletion
        latest = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanup()
            throw CaptureFailure.audioEngine(error.localizedDescription)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionGate.accepts(sessionID) else { return }
                if let result {
                    self.latest = result.bestTranscription.formattedString
                    self.partial?(self.latest)
                    if result.isFinal { self.complete(.success(self.latest), sessionID: sessionID) }
                } else if let error {
                    self.complete(.failure(.recognition(error.localizedDescription)), sessionID: sessionID)
                }
            }
        }
    }

    func stop() {
        request?.endAudio()
        stopEngine()
    }

    func cancel() {
        task?.cancel()
        request?.endAudio()
        stopEngine()
        cleanup()
    }

    private func complete(_ result: Result<String, CaptureFailure>, sessionID: UInt64) {
        guard sessionGate.accepts(sessionID) else { return }
        let callback = completion
        cleanup()
        callback?(result)
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func cleanup() {
        sessionGate.invalidate()
        stopEngine()
        request = nil
        task = nil
        partial = nil
        completion = nil
    }
}

@MainActor
final class ResultOverlay: NSWindowController {
    private let answer = NSTextField(labelWithString: "Ready")
    private let expression = NSTextField(wrappingLabelWithString: "Hold your shortcut and say a calculation")
    private let copyButton = NSButton(title: "Copy answer", target: nil, action: nil)
    private let closeButton = NSButton(title: "×", target: nil, action: nil)

    init() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 132))
        root.wantsLayer = true
        root.appearance = NSAppearance(named: .darkAqua)
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 0.97).cgColor
        root.layer?.cornerRadius = 18
        answer.font = .systemFont(ofSize: 34, weight: .semibold)
        answer.textColor = .white
        expression.font = .systemFont(ofSize: 12, weight: .regular)
        expression.textColor = .secondaryLabelColor
        answer.frame = NSRect(x: 24, y: 69, width: 312, height: 42)
        expression.frame = NSRect(x: 24, y: 31, width: 312, height: 38)
        let copy = copyButton
        copy.action = #selector(copyAnswer)
        copy.bezelStyle = .rounded
        copy.contentTintColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        copy.frame = NSRect(x: 24, y: 9, width: 112, height: 24)
        closeButton.bezelStyle = .texturedRounded
        closeButton.action = #selector(closeOverlay)
        closeButton.frame = NSRect(x: 322, y: 97, width: 24, height: 24)
        closeButton.toolTip = "Close result"
        closeButton.setAccessibilityLabel("Close result")
        root.addSubview(answer)
        root.addSubview(expression)
        root.addSubview(copy)
        root.addSubview(closeButton)
        let window = NSPanel(contentRect: root.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = root
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        super.init(window: window)
        copyButton.target = self
        closeButton.target = self
    }

    required init?(coder: NSCoder) { nil }

    func showStatus(_ text: String) {
        answer.stringValue = "Voice Calculator"
        answer.font = .systemFont(ofSize: 18, weight: .semibold)
        expression.stringValue = text
        copyButton.isEnabled = false
        copyButton.isHidden = true
        showAtTop()
    }

    func showResult(_ result: MathParser.Result) {
        answer.stringValue = MathParser.format(result.value)
        answer.font = .systemFont(ofSize: 34, weight: .semibold)
        expression.stringValue = result.expression
        copyButton.isEnabled = true
        copyButton.isHidden = false
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MathParser.format(result.value), forType: .string)
        showAtTop()
    }

    private func showAtTop() {
        guard let window else { return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        window.setFrameOrigin(NSPoint(x: screen.midX - window.frame.width / 2, y: screen.maxY - window.frame.height - 32))
        showWindow(nil)
        window.orderFrontRegardless()
    }

    @objc private func copyAnswer() {
        guard let text = answer.stringValue.nilIfEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func closeOverlay() { window?.orderOut(nil) }

    func smokeCheckStatusCopyIsDisabled() -> Bool {
        showStatus("Permission status smoke check")
        let disabled = !copyButton.isEnabled && copyButton.isHidden && closeButton.action == #selector(closeOverlay)
        window?.orderOut(nil)
        return disabled
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

@MainActor
final class SettingsWindow: NSWindowController {
    var onBindingChange: ((TriggerBinding) -> Void)?
    private let status = NSTextField(wrappingLabelWithString: "Permissions are requested only when you use the shortcut.")
    private var buttons: [NSButton] = []
    private var requestAccessButton: NSButton?

    init(binding: TriggerBinding) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 330))
        let title = NSTextField(labelWithString: "Voice Calculator Settings")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.frame = NSRect(x: 24, y: 280, width: 410, height: 30)
        root.addSubview(title)

        let shortcutTitle = NSTextField(labelWithString: "Hold to speak")
        shortcutTitle.font = .systemFont(ofSize: 14, weight: .medium)
        shortcutTitle.frame = NSRect(x: 24, y: 243, width: 410, height: 20)
        root.addSubview(shortcutTitle)
        for (index, option) in TriggerBinding.allCases.enumerated() {
            let button = NSButton(radioButtonWithTitle: option.label, target: nil, action: #selector(bindingSelected(_:)))
            button.tag = index
            button.state = option == binding ? .on : .off
            button.frame = NSRect(x: 26, y: 211 - index * 28, width: 400, height: 22)
            buttons.append(button)
            root.addSubview(button)
        }

        status.frame = NSRect(x: 24, y: 107, width: 410, height: 48)
        root.addSubview(status)
        let requestAccess = NSButton(title: "Request access", target: nil, action: #selector(requestPermissions))
        requestAccess.bezelStyle = .rounded
        requestAccess.frame = NSRect(x: 24, y: 67, width: 112, height: 28)
        root.addSubview(requestAccess)
        requestAccessButton = requestAccess
        let permissions = NSButton(title: "Check status", target: nil, action: #selector(checkPermissions))
        permissions.bezelStyle = .rounded
        permissions.frame = NSRect(x: 143, y: 67, width: 104, height: 28)
        root.addSubview(permissions)
        let openSettings = NSButton(title: "Open Privacy Settings", target: nil, action: #selector(openPrivacySettings))
        openSettings.bezelStyle = .rounded
        openSettings.frame = NSRect(x: 254, y: 67, width: 180, height: 28)
        root.addSubview(openSettings)
        let note = NSTextField(wrappingLabelWithString: "On-device English only. No online fallback. 30-second hold limit.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 24, y: 17, width: 410, height: 42)
        root.addSubview(note)

        let window = NSWindow(contentRect: root.bounds, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.contentView = root
        super.init(window: window)
        buttons.forEach { $0.target = self }
        requestAccess.target = self
        permissions.target = self
        openSettings.target = self
        refreshPermissions()
    }

    required init?(coder: NSCoder) { nil }

    @objc private func bindingSelected(_ sender: NSButton) {
        guard TriggerBinding.allCases.indices.contains(sender.tag) else { return }
        for button in buttons { button.state = button === sender ? .on : .off }
        onBindingChange?(TriggerBinding.allCases[sender.tag])
    }

    @objc private func checkPermissions() { refreshPermissions() }

    @objc private func requestPermissions() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        let requestMicrophone: () -> Void = { [weak self] in
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async { self?.refreshPermissions() }
                }
            } else {
                DispatchQueue.main.async { self?.refreshPermissions() }
            }
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in requestMicrophone() }
        } else {
            requestMicrophone()
        }
    }

    @objc private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
    }

    private func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        let micText = mic == .authorized ? "Microphone ready" : "Microphone permission needed"
        let speechText = speech == .authorized ? "Speech Recognition ready" : "Speech Recognition permission needed"
        let accessibilityText = AXIsProcessTrusted() ? "Shortcut access ready" : "Accessibility access needed for the global shortcut"
        status.stringValue = "\(micText). \(speechText). \(accessibilityText)."
    }

    func smokeCheckPermissionRequestAction() -> Bool {
        requestAccessButton?.target === self && requestAccessButton?.action == #selector(requestPermissions)
    }
}

@MainActor
final class VoiceCalcApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindow?
    private let overlay = ResultOverlay()
    private let driver = NativeSpeechDriver()
    private var coordinator: CaptureCoordinator!
    private var binding: TriggerBinding = .rightCommand
    private var tracker = HoldKeyTracker(binding: .rightCommand)
    private var eventMonitors: [Any] = []
    private var requestGate = CaptureRequestGate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let saved = UserDefaults.standard.object(forKey: "triggerKeyCode") as? UInt16,
           let stored = TriggerBinding(rawValue: saved) {
            binding = stored
            tracker = HoldKeyTracker(binding: stored)
        }
        coordinator = CaptureCoordinator(driver: driver)
        coordinator.onPhaseChange = { [weak self] phase in
            if phase == .listening { self?.overlay.showStatus("Listening…") }
            if phase == .finalizing { self?.overlay.showStatus("Finishing…") }
        }
        coordinator.onMaximumDuration = { [weak self] in self?.overlay.showStatus("30-second limit reached") }
        coordinator.onCompletion = { [weak self] result in self?.handle(result) }
        buildMenu()
        installKeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventMonitors.forEach(NSEvent.removeMonitor)
        coordinator.cancel()
        driver.cancel()
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "∑"
        statusItem.button?.toolTip = "Voice Calculator"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold \(binding.label) to speak", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "Quit Voice Calculator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func runSmokeChecks() -> Bool {
        buildMenu()
        defer { if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) } }
        guard let menu = statusItem.menu, menu.items.count == 4,
              menu.items[2].target === self, menu.items[3].target === NSApp else { return false }
        let settingsWindow = SettingsWindow(binding: binding)
        guard settingsWindow.smokeCheckPermissionRequestAction() else { return false }
        return overlay.smokeCheckStatusCopyIsDisabled()
    }

    @objc private func openSettings() {
        let window = SettingsWindow(binding: binding)
        window.onBindingChange = { [weak self] newBinding in self?.changeBinding(newBinding) }
        settings = window
        window.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func changeBinding(_ newBinding: TriggerBinding) {
        requestGate.bindingChanged()
        coordinator.cancel()
        binding = newBinding
        UserDefaults.standard.set(newBinding.rawValue, forKey: "triggerKeyCode")
        tracker = HoldKeyTracker(binding: newBinding)
        if let menu = statusItem.menu, let first = menu.items.first {
            first.title = "Hold \(newBinding.label) to speak"
        }
    }

    private func installKeyMonitor() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            let down = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(event.keyCode))
            Task { @MainActor in self?.handleModifierEvent(event, exactKeyDown: down) }
        }) { eventMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            let down = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(event.keyCode))
            Task { @MainActor in self?.handleModifierEvent(event, exactKeyDown: down) }
            return event
        }) { eventMonitors.append(local) }
    }

    private func handleModifierEvent(_ event: NSEvent, exactKeyDown: Bool) {
        switch tracker.flagsChanged(keyCode: event.keyCode, triggerKeyIsDown: exactKeyDown) {
        case .began:
            if let requestID = requestGate.press() { requestPermissionsThenCapture(requestID: requestID) }
        case .ended:
            requestGate.release()
            coordinator.release()
        case .none: break
        }
    }

    private func requestPermissionsThenCapture(requestID: UInt64) {
        guard coordinator.lifecycle.phase == .idle else { return }
        let startCapture = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.requestGate.completeRequest(requestID) else { return }
                guard SFSpeechRecognizer.authorizationStatus() == .authorized,
                      AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                      AXIsProcessTrusted() else {
                    self.overlay.showStatus("Allow Microphone, Speech, and Accessibility in Settings")
                    self.openSettings()
                    return
                }
                do {
                    guard SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition == true else {
                        throw CaptureFailure.onDeviceRecognitionUnavailable
                    }
                    if !self.coordinator.begin() { self.overlay.showStatus("Could not start capture") }
                } catch {
                    self.overlay.showStatus(error.localizedDescription)
                }
            }
        }
        func requestMic() {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .notDetermined { AVCaptureDevice.requestAccess(for: .audio) { _ in _ = startCapture() } }
            else { _ = startCapture() }
        }
        let speech = SFSpeechRecognizer.authorizationStatus()
        if speech == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in requestMic() }
        } else { requestMic() }
    }

    private func handle(_ result: Result<String, CaptureFailure>) {
        switch result {
        case .failure(let error): overlay.showStatus(error.localizedDescription)
        case .success(let transcript):
            do {
                let calculation = try CalculationValidator.evaluate(transcript)
                overlay.showResult(calculation)
            } catch {
                overlay.showStatus(error.localizedDescription)
            }
        }
    }
}

@main
enum VoiceCalcNativeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") {
            do {
                let result = try CalculationValidator.evaluate("2 plus 3 times 4")
                guard result.value == 14 else { Foundation.exit(1) }
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)
                let delegate = VoiceCalcApp()
                guard delegate.runSmokeChecks() else { Foundation.exit(1) }
                print("Voice Calculator self-test passed; menu, settings, and status checks ran without a listener or microphone.")
                return
            } catch {
                fputs("Native self-test failed: \(error)\n", stderr)
                Foundation.exit(1)
            }
        }
        let app = NSApplication.shared
        let delegate = VoiceCalcApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
