import SwiftUI

/// ValVoice audio visualizer — each bar ripples on its own phase-offset sine wave,
/// with the whole ensemble scaled by real microphone amplitude. Quiet → bars rest
/// at a flat baseline; speaking → bars dance with their own rhythm.
///
/// This is the same visual language as the web landing page's mini-pill animation,
/// but amplitude-driven so it reflects actual voice level instead of just looping.
struct AudioVisualizer: View {
    let audioMeter: AudioMeter      // current snapshot (re-passed each render)
    let sampler: () -> Float        // re-evaluated live on each tick
    let color: Color
    let isActive: Bool

    private let barCount = 15
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2.5
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 28

    @StateObject private var driver = RippleDriver()

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(isActive ? 0.95 : 0.55))
                    .frame(width: barWidth, height: barHeight(for: index))
            }
        }
        .frame(height: maxHeight)
        .onAppear { driver.start(sampler: sampler) }
        .onDisappear { driver.stop() }
        .onChange(of: isActive) { _, active in
            if !active { driver.amplitude = 0 }
        }
    }

    /// One bar's height = baseline + (amplitude × per-bar ripple).
    /// The ripple is a phased sine so each bar breathes at its own rhythm.
    private func barHeight(for index: Int) -> CGFloat {
        // Noise gate: ambient room-tone below ~0.1 doesn't drive the bars.
        let gated = max(0, driver.amplitude - 0.08) / 0.92
        // Soft compression so shouting doesn't just peg everything at max.
        let amp = CGFloat(pow(Double(gated), 0.55))
        // Per-bar phase offset — 15 bars stepping through the sine at different points.
        let phase = driver.phase + Double(index) * 0.42
        // Compound sines layered for more organic, less regular motion.
        let s1 = sin(phase)
        let s2 = sin(phase * 1.7) * 0.5
        let ripple = CGFloat(((s1 + s2) * 0.5 + 0.5))  // 0..1 (roughly)
        // Blend a small always-on baseline so bars never freeze to a flat line mid-speech.
        let intensity = amp * (0.35 + 0.65 * ripple)
        let raw = minHeight + intensity * (maxHeight - minHeight)
        return max(minHeight, min(maxHeight, raw))
    }
}

/// Ticks at 60 Hz, advancing the ripple phase and pulling the current amplitude.
/// Publishing triggers a SwiftUI redraw on the visualizer every frame.
final class RippleDriver: ObservableObject {
    @Published var amplitude: Float = 0
    @Published var phase: Double = 0

    private var sampler: (() -> Float)?
    private var timer: Timer?
    private var previous: Float = 0

    func start(sampler: @escaping () -> Float) {
        self.sampler = sampler
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let sampler = self.sampler else { return }
            // Attack/decay smoothing: follow up fast, release slow — feels like speech.
            let raw = max(0, min(1, sampler()))
            let next: Float = raw > self.previous
                ? self.previous + (raw - self.previous) * 0.55
                : self.previous + (raw - self.previous) * 0.12
            self.previous = next
            self.amplitude = next
            // Phase advances steadily; speed picks up slightly with amplitude so loud speech
            // ripples faster than quiet speech.
            self.phase += 0.26 + Double(next) * 0.2
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        amplitude = 0
        previous = 0
    }
}

/// Flat bars shown when the recorder is idle (no audio input)
struct StaticVisualizer: View {
    private let barCount = 9
    private let barWidth: CGFloat = 3.5
    private let barHeight: CGFloat = 5
    private let barSpacing: CGFloat = 3
    let color: Color

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                Capsule()
                    .fill(color.opacity(0.5))
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .frame(height: 28)
    }
}

// MARK: - Processing Status Display

struct ProcessingStatusDisplay: View {
    enum Mode {
        case transcribing
        case enhancing
    }

    let mode: Mode
    let color: Color

    private var label: String {
        switch mode {
        case .transcribing: return "Transcribing"
        case .enhancing:    return "Enhancing"
        }
    }

    private var animationSpeed: Double {
        switch mode {
        case .transcribing: return 0.18
        case .enhancing:    return 0.22
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .foregroundColor(color)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            ProgressAnimation(color: color, animationSpeed: animationSpeed)
        }
        .frame(height: 28) // matches AudioVisualizer maxHeight to prevent layout shift
    }
}
