import Foundation

enum TriggerBinding: UInt16, CaseIterable {
    case rightOption = 61
    case rightCommand = 54
    case leftOption = 58

    var label: String {
        switch self {
        case .rightOption: return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        case .leftOption: return "Left Option (⌥)"
        }
    }
}

enum HoldTransition: Equatable {
    case began
    case ended
    case none
}

struct HoldKeyTracker {
    private(set) var isHolding = false
    let binding: TriggerBinding

    mutating func flagsChanged(keyCode: UInt16, triggerKeyIsDown: Bool) -> HoldTransition {
        guard keyCode == binding.rawValue else { return .none }
        if triggerKeyIsDown && !isHolding {
            isHolding = true
            return .began
        }
        if !triggerKeyIsDown && isHolding {
            isHolding = false
            return .ended
        }
        return .none
    }
}

struct RecognitionSessionGate {
    private(set) var currentID: UInt64 = 0

    mutating func begin() -> UInt64 {
        currentID &+= 1
        return currentID
    }

    mutating func invalidate() {
        currentID &+= 1
    }

    func accepts(_ sessionID: UInt64) -> Bool { sessionID == currentID }
}

struct CaptureRequestGate {
    private(set) var isTriggerHeld = false
    private(set) var isRequestInFlight = false
    private(set) var generation: UInt64 = 0

    mutating func press() -> UInt64? {
        isTriggerHeld = true
        guard !isRequestInFlight else { return nil }
        isRequestInFlight = true
        generation &+= 1
        return generation
    }

    mutating func release() {
        isTriggerHeld = false
        isRequestInFlight = false
        generation &+= 1
    }

    mutating func bindingChanged() { release() }

    mutating func completeRequest(_ requestID: UInt64) -> Bool {
        guard generation == requestID, isTriggerHeld, isRequestInFlight else { return false }
        isRequestInFlight = false
        return true
    }
}

enum CapturePhase: Equatable {
    case idle
    case listening
    case finalizing
}

struct CaptureLifecycle {
    private(set) var phase: CapturePhase = .idle

    mutating func begin() -> Bool {
        guard phase == .idle else { return false }
        phase = .listening
        return true
    }

    mutating func release() -> Bool {
        guard phase == .listening else { return false }
        phase = .finalizing
        return true
    }

    mutating func finish() -> Bool {
        guard phase != .idle else { return false }
        phase = .idle
        return true
    }

    mutating func cancel() -> Bool {
        guard phase != .idle else { return false }
        phase = .idle
        return true
    }
}

enum CaptureFailure: Error, LocalizedError, Equatable {
    case onDeviceRecognitionUnavailable
    case speechRecognizerUnavailable
    case audioEngine(String)
    case recognition(String)
    case noSpeech
    case finalResultTimedOut
    case transcriptTooLong

    var errorDescription: String? {
        switch self {
        case .onDeviceRecognitionUnavailable:
            return "On-device speech recognition is unavailable for English. No audio was sent online."
        case .speechRecognizerUnavailable:
            return "Speech recognition is unavailable for English on this Mac."
        case .audioEngine(let detail):
            return "Microphone could not start: \(detail)"
        case .recognition(let detail):
            return "Speech recognition stopped: \(detail)"
        case .noSpeech:
            return "No calculation was recognized."
        case .finalResultTimedOut:
            return "Speech recognition did not return a result in time."
        case .transcriptTooLong:
            return "That request is too long. Keep it under 2,048 characters."
        }
    }
}

@MainActor
protocol SpeechCaptureDriver: AnyObject {
    func start(
        onPartial: @escaping (String) -> Void,
        onCompletion: @escaping (Result<String, CaptureFailure>) -> Void
    ) throws
    func stop()
    func cancel()
}

@MainActor
final class CaptureCoordinator {
    private(set) var lifecycle = CaptureLifecycle()
    private let driver: SpeechCaptureDriver
    private let maximumDuration: TimeInterval
    private let finalizationTimeout: TimeInterval
    private var durationWork: DispatchWorkItem?
    private var finalizationWork: DispatchWorkItem?
    private var generation: UInt64 = 0
    private var latestTranscript = ""
    var onPartial: ((String) -> Void)?
    var onCompletion: ((Result<String, CaptureFailure>) -> Void)?
    var onMaximumDuration: (() -> Void)?
    var onPhaseChange: ((CapturePhase) -> Void)?

    init(
        driver: SpeechCaptureDriver,
        maximumDuration: TimeInterval = 30,
        finalizationTimeout: TimeInterval = 1.2
    ) {
        self.driver = driver
        self.maximumDuration = max(1, maximumDuration)
        self.finalizationTimeout = max(0.1, finalizationTimeout)
    }

    @discardableResult
    func begin() -> Bool {
        guard lifecycle.begin() else { return false }
        generation &+= 1
        let captureID = generation
        latestTranscript = ""
        onPhaseChange?(.listening)
        do {
            try driver.start(
                onPartial: { [weak self] text in self?.receivePartial(text, captureID: captureID) },
                onCompletion: { [weak self] result in self?.receiveCompletion(result, captureID: captureID) }
            )
        } catch let failure as CaptureFailure {
            finish(.failure(failure), captureID: captureID)
            return false
        } catch {
            finish(.failure(.recognition(error.localizedDescription)), captureID: captureID)
            return false
        }
        guard generation == captureID, lifecycle.phase == .listening else { return true }
        let work = DispatchWorkItem { [weak self] in self?.maximumDurationReached(captureID: captureID) }
        durationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maximumDuration, execute: work)
        return true
    }

    func release() {
        guard lifecycle.release() else { return }
        durationWork?.cancel()
        durationWork = nil
        onPhaseChange?(.finalizing)
        driver.stop()
        let captureID = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == captureID, self.lifecycle.phase == .finalizing else { return }
            if self.latestTranscript.isEmpty {
                self.driver.cancel()
                self.finish(.failure(.finalResultTimedOut), captureID: captureID)
            } else {
                self.finish(.success(self.latestTranscript), captureID: captureID)
            }
        }
        finalizationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + finalizationTimeout, execute: work)
    }

    func cancel() {
        guard lifecycle.cancel() else { return }
        generation &+= 1
        cancelTimers()
        driver.cancel()
        latestTranscript = ""
        onPhaseChange?(.idle)
    }

    private func maximumDurationReached(captureID: UInt64) {
        guard generation == captureID, lifecycle.phase == .listening else { return }
        onMaximumDuration?()
        release()
    }

    private func receivePartial(_ text: String, captureID: UInt64) {
        guard generation == captureID, lifecycle.phase != .idle else { return }
        guard text.count <= 2_048 else {
            finish(.failure(.transcriptTooLong), captureID: captureID)
            return
        }
        latestTranscript = text
        onPartial?(text)
    }

    private func receiveCompletion(_ result: Result<String, CaptureFailure>, captureID: UInt64) {
        finish(result, captureID: captureID)
    }

    private func finish(_ result: Result<String, CaptureFailure>, captureID: UInt64) {
        guard generation == captureID, lifecycle.finish() else { return }
        cancelTimers()
        driver.cancel()
        onPhaseChange?(.idle)
        onCompletion?(result)
    }

    private func cancelTimers() {
        durationWork?.cancel()
        durationWork = nil
        finalizationWork?.cancel()
        finalizationWork = nil
    }
}

enum CalculationFailure: Error, LocalizedError, Equatable {
    case transcriptTooLong
    case nonFiniteResult

    var errorDescription: String? {
        switch self {
        case .transcriptTooLong: return "That request is too long. Keep it under 2,048 characters."
        case .nonFiniteResult: return "That calculation does not have a finite result."
        }
    }
}

enum CalculationValidator {
    static func evaluate(_ transcript: String) throws -> MathParser.Result {
        guard transcript.count <= 2_048 else { throw CalculationFailure.transcriptTooLong }
        let result = try MathParser.evaluate(transcript)
        guard result.value.isFinite else { throw CalculationFailure.nonFiniteResult }
        return result
    }
}
