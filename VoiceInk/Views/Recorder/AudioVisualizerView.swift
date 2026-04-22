import SwiftUI

/// ValVoice audio visualizer — Siri-style sine wave plus event-driven ripples.
///
/// Two visual layers, both synced to the mic:
/// 1. A sinusoidal line that bends with your voice. Quiet = near-flat; loud = big
///    sweeping wave. Amplitude of the bend is driven by real audio; phase advances
///    over time (faster when louder).
/// 2. Discrete ripple dots that spawn on each peak event (syllable onset), drifting
///    outward from center and fading. Every "hit" of speech gets its own echo.
///
/// The wave gives continuous feedback, the ripples give discrete per-syllable feedback.
/// Together you get an extremely responsive, organic-feeling visualizer.
struct AudioVisualizer: View {
    let audioMeter: AudioMeter
    let sampler: () -> Float
    let color: Color
    let isActive: Bool

    private let visualWidth: CGFloat = 92
    private let visualHeight: CGFloat = 28

    @StateObject private var driver = WaveRippleDriver()

    var body: some View {
        ZStack {
            // Ripples behind the wave so the wave "emits" them
            ForEach(driver.ripples) { ripple in
                RippleView(ripple: ripple, color: color, height: visualHeight)
            }

            // Siri-style sine wave
            WaveShape(amplitude: driver.waveAmplitude, phase: driver.phase)
                .stroke(
                    color.opacity(isActive ? 0.92 : 0.4),
                    style: StrokeStyle(lineWidth: 1.6 + CGFloat(driver.waveAmplitude) * 1.8,
                                       lineCap: .round,
                                       lineJoin: .round)
                )
                .shadow(color: color.opacity(driver.waveAmplitude * 0.55),
                        radius: 2 + driver.waveAmplitude * 8)
        }
        .frame(width: visualWidth, height: visualHeight)
        .onAppear { driver.start(sampler: sampler) }
        .onDisappear { driver.stop() }
        .onChange(of: isActive) { _, active in
            if !active { driver.reset() }
        }
    }
}

/// A horizontal sine curve that tapers to zero at the edges.
/// `amplitude` ∈ 0…1 scales how tall the wave peaks are.
/// `phase` animates the wave scrolling over time.
struct WaveShape: Shape {
    var amplitude: Double
    var phase: Double

    // Let SwiftUI animate phase + amplitude smoothly between ticks
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(amplitude, phase) }
        set {
            amplitude = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let width = rect.width
        // Wave occupies up to ~42% of height when at full amplitude
        let maxSwing = rect.height * 0.42

        let samples = max(32, Int(width))
        for i in 0...samples {
            let t = Double(i) / Double(samples)         // 0…1
            let x = CGFloat(t) * width

            // Tapered envelope — zero at both ends, 1 in the middle.
            // Uses a smooth cosine shape so the wave vanishes cleanly.
            let envelope = sin(t * .pi)

            // Two sine wavelengths across the pill width, scrolled by phase.
            let wave = sin(t * .pi * 4 + phase)

            // Compound with a secondary harmonic for less regular motion.
            let harmonic = sin(t * .pi * 8 + phase * 1.3) * 0.25

            let y = midY - CGFloat((wave + harmonic) * envelope) * CGFloat(amplitude) * maxSwing

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

/// A single ripple event — drifts outward from center, fades over its lifetime.
struct RippleState: Identifiable, Equatable {
    let id = UUID()
    let spawnTime: TimeInterval
    let direction: CGFloat       // -1 = left, +1 = right
    let initialAmplitude: Double // snap of the peak that triggered this ripple

    static let lifetime: TimeInterval = 0.85

    func progress(at now: TimeInterval) -> Double {
        let elapsed = now - spawnTime
        return min(1.0, max(0.0, elapsed / Self.lifetime))
    }

    func isDead(at now: TimeInterval) -> Bool {
        (now - spawnTime) > Self.lifetime
    }
}

struct RippleView: View {
    let ripple: RippleState
    let color: Color
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0, paused: false)) { ctx in
            let now = ctx.date.timeIntervalSince1970
            let p = ripple.progress(at: now)
            let drift = ripple.direction * CGFloat(p) * 34  // px outward
            let size = 3.5 + CGFloat(p) * 4                 // grows as it fades
            let opacity = (1.0 - p) * (0.3 + ripple.initialAmplitude * 0.55)

            Circle()
                .fill(color.opacity(opacity))
                .frame(width: size, height: size)
                .offset(x: drift, y: 0)
        }
    }
}

/// Drives both the wave and the ripples. 60 Hz tick, reads amplitude, detects peak events.
final class WaveRippleDriver: ObservableObject {
    @Published var waveAmplitude: Double = 0    // smoothed for the wave
    @Published var phase: Double = 0
    @Published var ripples: [RippleState] = []

    private var sampler: (() -> Float)?
    private var timer: Timer?
    private var smoothed: Float = 0
    private var previous: Float = 0
    private var lastSpawnAt: TimeInterval = 0

    func start(sampler: @escaping () -> Float) {
        self.sampler = sampler
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let sampler else { return }
        let raw = max(0, min(1, sampler()))

        // Noise gate + soft compression — aggressive so small voice = visible motion
        let gated = max(0, raw - 0.06) / 0.94
        let compressed = pow(Double(gated), 0.4)  // gentler curve = more dynamic range in middle

        // Attack/decay for wave amplitude
        let attack: Float = 0.7
        let decay: Float = 0.11
        let target = Float(compressed)
        smoothed = target > smoothed
            ? smoothed + (target - smoothed) * attack
            : smoothed + (target - smoothed) * decay
        waveAmplitude = Double(smoothed)

        // Phase scrolls faster when louder
        phase += 0.14 + Double(smoothed) * 0.45

        // Ripple trigger: rising peak above threshold, debounced
        let now = Date().timeIntervalSince1970
        let delta = raw - previous
        if delta > 0.14 && raw > 0.2 && (now - lastSpawnAt) > 0.08 {
            ripples.append(RippleState(spawnTime: now, direction: -1, initialAmplitude: Double(raw)))
            ripples.append(RippleState(spawnTime: now, direction: 1, initialAmplitude: Double(raw)))
            lastSpawnAt = now
        }
        previous = raw

        // Reap dead ripples
        ripples.removeAll { $0.isDead(at: now) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reset()
    }

    func reset() {
        waveAmplitude = 0
        phase = 0
        ripples.removeAll()
        smoothed = 0
        previous = 0
    }
}

/// Idle state — a dim hairline, matching the active visualizer's resting form.
struct StaticVisualizer: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color.opacity(0.35))
            .frame(width: 72, height: 1.6)
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
        .frame(height: 28)
    }
}
