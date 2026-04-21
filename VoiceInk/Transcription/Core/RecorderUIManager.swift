import Foundation
import SwiftUI
import os

@MainActor
class RecorderUIManager: ObservableObject {
    @Published var miniRecorderError: String?

    // ValVoice: interface style locked to "mini" — no longer user-configurable.
    // Kept as a stored property so ImportExportService and other call sites compile,
    // but setter ignores assignments and getter always returns "mini".
    @Published var recorderType: String = "mini" {
        didSet {
            if recorderType != "mini" {
                recorderType = "mini"
            }
        }
    }

    @Published var isMiniRecorderVisible = false {
        didSet {
            Task { @MainActor in
                if isMiniRecorderVisible {
                    showRecorderPanel()
                } else {
                    hideRecorderPanel()
                }
            }
        }
    }

    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?

    private weak var engine: ValVoiceEngine?
    private var recorder: Recorder?

    private let logger = Logger(subsystem: "com.nicolaivalenta.valvoice", category: "RecorderUIManager")

    init() {}

    /// Call after ValVoiceEngine is created to break the circular init dependency.
    func configure(engine: ValVoiceEngine, recorder: Recorder) {
        self.engine = engine
        self.recorder = recorder
        setupNotifications()
    }

    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        guard let engine = engine, let recorder = recorder else { return }
        logger.notice("Showing \(self.recorderType, privacy: .public) recorder")

        if recorderType == "notch" {
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(engine: engine, recorder: recorder)
            }
            notchWindowManager?.show()
        } else {
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(engine: engine, recorder: recorder)
            }
            miniWindowManager?.show()
        }
    }

    func hideRecorderPanel() {
        if recorderType == "notch" {
            notchWindowManager?.hide()
        } else {
            miniWindowManager?.hide()
        }
    }

    // MARK: - Mini Recorder Management

    private var isCapsLockHotkey: Bool {
        let key = UserDefaults.standard.string(forKey: "selectedHotkey1") ?? ""
        let key2 = UserDefaults.standard.string(forKey: "selectedHotkey2") ?? ""
        return key == "capsLock" || key2 == "capsLock"
    }

    func toggleMiniRecorder(powerModeId: UUID? = nil) async {
        guard let engine = engine else { return }
        logger.notice("toggleMiniRecorder called – visible=\(self.isMiniRecorderVisible, privacy: .public), state=\(String(describing: engine.recordingState), privacy: .public)")

        if isMiniRecorderVisible {
            if engine.recordingState == .recording {
                logger.notice("toggleMiniRecorder: stopping recording (was recording)")
                if isCapsLockHotkey { HotkeyManager.setCapsLockLED(false) }
                await engine.toggleRecord(powerModeId: powerModeId)
            } else {
                logger.notice("toggleMiniRecorder: cancelling (was not recording)")
                if isCapsLockHotkey { HotkeyManager.setCapsLockLED(false) }
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound()
            if isCapsLockHotkey { HotkeyManager.setCapsLockLED(true) }
            await MainActor.run { isMiniRecorderVisible = true }
            await engine.toggleRecord(powerModeId: powerModeId)
        }
    }

    func dismissMiniRecorder() async {
        guard let engine = engine, let recorder = recorder else { return }
        logger.notice("dismissMiniRecorder called – state=\(String(describing: engine.recordingState), privacy: .public)")
        if isCapsLockHotkey { HotkeyManager.setCapsLockLED(false) }

        if engine.recordingState == .busy {
            logger.notice("dismissMiniRecorder: early return, state is busy")
            return
        }

        let wasRecording = engine.recordingState == .recording

        await MainActor.run {
            engine.recordingState = .busy
        }

        // Cancel and release any active streaming session to prevent resource leaks.
        engine.currentSession?.cancel()
        engine.currentSession = nil

        if wasRecording {
            await recorder.stopRecording()
        }

        hideRecorderPanel()

        // Clear captured context when the recorder is dismissed
        if let enhancementService = engine.enhancementService {
            await MainActor.run {
                enhancementService.clearCapturedContexts()
            }
        }

        await MainActor.run {
            isMiniRecorderVisible = false
        }

        await engine.cleanupResources()

        if UserDefaults.standard.bool(forKey: PowerModeDefaults.autoRestoreKey) {
            await PowerModeSessionManager.shared.endSession()
            await MainActor.run {
                PowerModeManager.shared.setActiveConfiguration(nil)
            }
        }

        await MainActor.run {
            engine.recordingState = .idle
        }
        logger.notice("dismissMiniRecorder completed")
    }

    func resetOnLaunch() async {
        guard let engine = engine, let recorder = recorder else { return }
        logger.notice("Resetting recording state on launch")
        await recorder.stopRecording()
        hideRecorderPanel()
        await MainActor.run {
            isMiniRecorderVisible = false
            engine.shouldCancelRecording = false
            miniRecorderError = nil
            engine.recordingState = .idle
        }
        await engine.cleanupResources()
    }

    func cancelRecording() async {
        guard let engine = engine else { return }
        logger.notice("cancelRecording called")
        SoundManager.shared.playEscSound()
        engine.shouldCancelRecording = true
        await dismissMiniRecorder()
    }

    // MARK: - Notification Handling

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleMiniRecorder),
            name: .toggleMiniRecorder,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissMiniRecorder),
            name: .dismissMiniRecorder,
            object: nil
        )
    }

    @objc public func handleToggleMiniRecorder() {
        logger.notice("handleToggleMiniRecorder: .toggleMiniRecorder notification received")
        Task {
            await toggleMiniRecorder()
        }
    }

    @objc public func handleDismissMiniRecorder() {
        logger.notice("handleDismissMiniRecorder: .dismissMiniRecorder notification received")
        Task {
            await dismissMiniRecorder()
        }
    }
}
