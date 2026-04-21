import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService

    @State private var activePopover: ActivePopoverState = .none

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 36
    private let compactWidth: CGFloat = 110  // tight fit around the audio bars only
    private let compactCornerRadius: CGFloat = 18

    // ValVoice: live transcript preview removed. Users don't want to read themselves typing
    // in real time — it's distracting. Only show the compact audio-meter pill.

    private var controlBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeter: recorder.audioMeter,
                sampler: { [weak recorder] in Float(recorder?.audioMeter.averagePower ?? 0) }
            )

            Spacer(minLength: 0)
        }
        .frame(height: controlBarHeight)
    }

    var body: some View {
        if windowManager.isVisible {
            controlBar
                .frame(width: compactWidth)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
