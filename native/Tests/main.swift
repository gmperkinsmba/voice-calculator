import Foundation

@MainActor
final class FakeDriver: SpeechCaptureDriver {
    var partial: ((String) -> Void)?
    var completion: ((Result<String, CaptureFailure>) -> Void)?
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0
    var startError: CaptureFailure?

    func start(onPartial: @escaping (String) -> Void,
               onCompletion: @escaping (Result<String, CaptureFailure>) -> Void) throws {
        starts += 1
        if let startError { throw startError }
        partial = onPartial
        completion = onCompletion
    }

    func stop() { stops += 1 }
    func cancel() { cancels += 1 }
}

@MainActor
enum NativeCoreTests {
    static var failures = 0
    static var passed = 0

    static func check(_ name: String, _ body: () throws -> Bool) {
        do {
            if try body() { passed += 1; print("ok  \(name)") }
            else { failures += 1; print("FAIL  \(name)") }
        } catch {
            failures += 1
            print("FAIL  \(name): \(error)")
        }
    }

    static func run() async {
        check("default binding is right command") { TriggerBinding.rightCommand.rawValue == 54 }
        check("supported bindings are distinct physical keys") {
            Set(TriggerBinding.allCases.map(\.rawValue)) == Set([54, 58, 61])
        }
        check("matching keydown begins hold") {
            var tracker = HoldKeyTracker(binding: .rightOption)
            return tracker.flagsChanged(keyCode: 61, triggerKeyIsDown: true) == .began
        }
        check("unrelated modifier does not sustain configured key") {
            var tracker = HoldKeyTracker(binding: .rightCommand)
            _ = tracker.flagsChanged(keyCode: 54, triggerKeyIsDown: true)
            return tracker.flagsChanged(keyCode: 54, triggerKeyIsDown: false) == .ended
        }
        check("events from other keycodes are ignored") {
            var tracker = HoldKeyTracker(binding: .leftOption)
            return tracker.flagsChanged(keyCode: 61, triggerKeyIsDown: false) == .none
        }
        check("old speech task callbacks are rejected after a new capture") {
            var gate = RecognitionSessionGate()
            let first = gate.begin()
            gate.invalidate()
            let second = gate.begin()
            return !gate.accepts(first) && gate.accepts(second)
        }
        check("binding change invalidates pending permission request") {
            var gate = CaptureRequestGate()
            guard let pending = gate.press() else { return false }
            gate.bindingChanged()
            return !gate.completeRequest(pending) && !gate.isTriggerHeld && !gate.isRequestInFlight
        }
        check("released key blocks late permission callback") {
            var gate = CaptureRequestGate()
            guard let pending = gate.press() else { return false }
            gate.release()
            return !gate.completeRequest(pending) && !gate.isTriggerHeld
        }
        check("release enters finalizing once") {
            var state = CaptureLifecycle()
            return state.begin() && state.release() && !state.release() && state.finish()
        }
        check("calculation keeps order of operations") {
            try CalculationValidator.evaluate("2 plus 3 times 4").value == 14
        }
        check("divide by zero is rejected") {
            do { _ = try CalculationValidator.evaluate("1 divided by 0"); return false }
            catch MathParser.ParseError.divideByZero { return true }
        }
        check("nonfinite result is rejected") {
            do { _ = try CalculationValidator.evaluate("2 to the power of 100000"); return false }
            catch CalculationFailure.nonFiniteResult { return true }
        }
        check("oversized transcript is rejected") {
            do { _ = try CalculationValidator.evaluate(String(repeating: "1", count: 2_049)); return false }
            catch CalculationFailure.transcriptTooLong { return true }
        }
        check("bounded transcript evaluates") {
            try CalculationValidator.evaluate("6 times 7").value == 42
        }
        check("oversized live recognition fails and cancels audio") {
            let driver = FakeDriver()
            let coordinator = CaptureCoordinator(driver: driver)
            var error: CaptureFailure?
            coordinator.onCompletion = { result in if case .failure(let failure) = result { error = failure } }
            _ = coordinator.begin()
            driver.partial?(String(repeating: "x", count: 2_049))
            return error == .transcriptTooLong && coordinator.lifecycle.phase == .idle && driver.cancels == 1
        }
        check("cancel invalidates late recognition callbacks") {
            let driver = FakeDriver()
            let coordinator = CaptureCoordinator(driver: driver)
            var completions = 0
            coordinator.onCompletion = { _ in completions += 1 }
            _ = coordinator.begin()
            let stale = driver.completion
            coordinator.cancel()
            _ = coordinator.begin()
            stale?(.success("1 plus 2"))
            guard completions == 0, coordinator.lifecycle.phase == .listening else { return false }
            driver.completion?(.success("3 plus 4"))
            return completions == 1 && coordinator.lifecycle.phase == .idle && driver.cancels == 2
        }
        check("release stops input and uses partial transcript at timeout") {
            let driver = FakeDriver()
            let coordinator = CaptureCoordinator(driver: driver, finalizationTimeout: 0.1)
            var text: String?
            coordinator.onCompletion = { result in if case .success(let value) = result { text = value } }
            _ = coordinator.begin()
            driver.partial?("8 times 9")
            coordinator.release()
            RunLoop.main.run(until: Date().addingTimeInterval(0.18))
            return driver.stops == 1 && text == "8 times 9" && coordinator.lifecycle.phase == .idle
        }
        check("empty finalization reports timeout") {
            let driver = FakeDriver()
            let coordinator = CaptureCoordinator(driver: driver, finalizationTimeout: 0.1)
            var error: CaptureFailure?
            _ = coordinator.begin()
            coordinator.onCompletion = { result in if case .failure(let failure) = result { error = failure } }
            coordinator.release()
            RunLoop.main.run(until: Date().addingTimeInterval(0.18))
            return error == .finalResultTimedOut && coordinator.lifecycle.phase == .idle
        }
        check("driver start error returns capture to idle") {
            let driver = FakeDriver()
            driver.startError = .audioEngine("unavailable")
            let coordinator = CaptureCoordinator(driver: driver)
            var error: CaptureFailure?
            coordinator.onCompletion = { result in if case .failure(let failure) = result { error = failure } }
            let started = coordinator.begin()
            return !started && error == .audioEngine("unavailable") && coordinator.lifecycle.phase == .idle
        }
        print("\n\(passed) passed, \(failures) failed")
        if failures > 0 { Foundation.exit(1) }
    }
}

@main
enum NativeTestsMain {
    @MainActor static func main() async {
        await NativeCoreTests.run()
    }
}
