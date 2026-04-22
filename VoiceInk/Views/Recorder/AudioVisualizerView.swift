import SwiftUI

/// ValVoice audio visualizer — a single horizontal line that thickens and glows
/// with your voice. Silent = a hairline wire. Speech = a bright, glowing beam.
/// No pulses when quiet, no fake motion — just honest amplitude feedback.
struct AudioVisualizer: View {
    let audioMeter: AudioMeter      // current snapshot (re-passed each render)
    let sampler: () -> Float        // re-evaluated live on each tick
    let color: Color
    let isActive: Bool

    // Line geometry
    private let lineMinThickness: CGFloat = 2
    private let lineMaxThickness: CGFloat = 9
    private let lineWidth: CGFloat = 72
    private let containerHeight: CGFloat = 28

    @StateObject private var driver = AmplitudeDriver()

    var body: some View {
        // Amplitude 0..1, with noise gate and soft compression so quiet sounds don't trip it.
        let gated = max(0, driver.amplitude - 0.08) / 0.92
        let amp = CGFloat(pow(Double(gated), 0.55))

        let thickness = lineMinThickness + amp * (lineMaxThickness - lineMinThickness)
        let glowRadius = 2 + amp * 10
        let fill = color.opacity(isActive ? (0.55 + 0.45 * amp) : 0.35)

        return Capsule()
            .fill(fill)
            .frame(width: lineWidth, height: thickness)
            .shadow(color: color.opacity(isActive ? 0.55 * amp : 0), radius: glowRadius, x: 0, y: 0)
            .frame(height: containerHeight)
            .onAppear { driver.start(sampler: sampler) }
            .onDisappear { driver.stop() }
            .onChange(of: isActive) { _, active in
                if !active { driver.amplitude = 0 }
            }
    }
}

/// Ticks at 60 Hz, pulling current amplitude with attack/decay smoothing so the
/// line feels responsive on voice onset and relaxes gently when quiet.
final class AmplitudeDriver: ObservableObject {
    @Published var amplitude: Float = 0

    private var sampler: (() -> Float)?
    private var timer: Timer?
    private var previous: Float = 0

    func start(sampler: @escaping () -> Float) {
        self.sampler = sampler
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let sampler = self.sampler else { return }
            let raw = max(0, min(1, sampler()))
            // Fast attack (voice onset snaps the line thicker), slow decay (quiet fades softly).
            let next: Float = raw > self.previous
                ? self.previous + (raw - self.previous) * 0.55
                : self.previous + (raw - self.previous) * 0.1
            self.previous = next
            self.amplitude = next
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        amplitude = 0
        previous = 0
    }
}

/// Idle state — a dim hairline wire, matching the active visualizer's resting form.
struct StaticVisualizer: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color.opacity(0.35))
            .frame(width: 72, height: 2)
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
