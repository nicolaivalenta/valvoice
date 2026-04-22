import SwiftUI

/// ValVoice audio visualizer — fixed control-point spline that wiggles in place.
///
/// 7 control points sit at fixed positions along the pill. Endpoints are pinned
/// at center height. Each interior point oscillates at its own natural frequency,
/// scaled by the current voice amplitude. A smooth Catmull-Rom spline is drawn
/// through them. Silent = flat line. Speaking = a snake wiggling in place, never
/// traveling left or right.
///
/// Layered on top: event-driven ripple dots that spawn from center on each
/// syllable peak — discrete feedback for each "hit" of speech.
struct AudioVisualizer: View {
    let audioMeter: AudioMeter
    let sampler: () -> Float
    let color: Color
    let isActive: Bool

    private let visualWidth: CGFloat = 92
    private let visualHeight: CGFloat = 28

    @StateObject private var driver = SplineDriver(count: 7)

    var body: some View {
        ZStack {
            // Ripples behind the spline
            ForEach(driver.ripples) { ripple in
                RippleView(ripple: ripple, color: color, height: visualHeight)
            }

            // The wiggling spline
            SplineShape(yValues: driver.yValues)
                .stroke(
                    color.opacity(isActive ? 0.92 : 0.4),
                    style: StrokeStyle(lineWidth: 1.6 + CGFloat(driver.intensity) * 1.6,
                                       lineCap: .round,
                                       lineJoin: .round)
                )
                .shadow(color: color.opacity(driver.intensity * 0.55),
                        radius: 2 + driver.intensity * 7)
        }
        .frame(width: visualWidth, height: visualHeight)
        .onAppear { driver.start(sampler: sampler) }
        .onDisappear { driver.stop() }
        .onChange(of: isActive) { _, active in
            if !active { driver.reset() }
        }
    }
}

/// Smooth curve through a fixed set of control points, drawn with Catmull-Rom spline.
struct SplineShape: Shape {
    let yValues: [Double]   // −1…1 range (0 = center of pill)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let n = yValues.count
        guard n >= 2 else { return path }

        let midY = rect.midY
        let maxSwing = rect.height * 0.4
        let stepX = rect.width / CGFloat(n - 1)

        let points: [CGPoint] = yValues.enumerated().map { i, y in
            CGPoint(x: CGFloat(i) * stepX,
                    y: midY - CGFloat(y) * maxSwing)
        }

        path.move(to: points[0])
        for i in 0..<(n - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i < n - 2 ? points[i + 2] : points[i + 1]

            // Catmull-Rom → cubic Bezier control points
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                             y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                             y: p2.y - (p3.y - p1.y) / 6)

            path.addCurve(to: p2, control1: c1, control2: c2)
        }

        return path
    }
}

/// A single ripple event — drifts outward from center, fades over its lifetime.
struct RippleState: Identifiable, Equatable {
    let id = UUID()
    let spawnTime: TimeInterval
    let direction: CGFloat       // -1 = left, +1 = right
    let initialAmplitude: Double

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
            let drift = ripple.direction * CGFloat(p) * 34
            let size = 3.5 + CGFloat(p) * 4
            let opacity = (1.0 - p) * (0.3 + ripple.initialAmplitude * 0.55)

            Circle()
                .fill(color.opacity(opacity))
                .frame(width: size, height: size)
                .offset(x: drift, y: 0)
        }
    }
}

/// Drives the 7-point spline. Each interior point has its own oscillation
/// frequency and phase — so the curve wiggles in place without scrolling.
/// Event-driven ripples spawn on peak voice onset.
final class SplineDriver: ObservableObject {
    @Published var yValues: [Double]
    @Published var intensity: Double = 0
    @Published var ripples: [RippleState] = []

    private let count: Int
    private let frequencies: [Double]
    private let phases: [Double]

    private var startTime: TimeInterval = 0
    private var sampler: (() -> Float)?
    private var timer: Timer?
    private var smoothed: Float = 0
    private var previous: Float = 0
    private var lastSpawnAt: TimeInterval = 0

    init(count: Int) {
        self.count = count
        // Prime numbers-ish frequencies so interior points never line up — prevents
        // the wave from looking coherent / traveling in any direction.
        self.frequencies = (0..<count).map { i in
            // Interior point ranges from ~4–10 Hz, spread out
            if i == 0 || i == count - 1 { return 0 }
            return 3.8 + Double(i) * 0.93
        }
        self.phases = (0..<count).map { i in
            Double(i) * 1.43  // deterministic but non-repeating phase offsets
        }
        self.yValues = Array(repeating: 0, count: count)
    }

    func start(sampler: @escaping () -> Float) {
        self.sampler = sampler
        self.startTime = Date().timeIntervalSince1970
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let sampler else { return }
        let raw = max(0, min(1, sampler()))

        // Noise gate above typical room tone
        let gateFloor: Float = 0.18
        let gated = max(0, raw - gateFloor) / (1 - gateFloor)
        var compressed = pow(Double(gated), 0.7)
        if compressed < 0.04 { compressed = 0 }

        // Fast attack, slow decay
        let attack: Float = 0.6
        let decay: Float = 0.12
        let target = Float(compressed)
        smoothed = target > smoothed
            ? smoothed + (target - smoothed) * attack
            : smoothed + (target - smoothed) * decay
        if smoothed < 0.015 { smoothed = 0 }
        intensity = Double(smoothed)

        // Each interior point oscillates; endpoints stay pinned at 0.
        let now = Date().timeIntervalSince1970
        let elapsed = now - startTime
        let amp = Double(smoothed)

        for i in 0..<count {
            if i == 0 || i == count - 1 {
                yValues[i] = 0  // pinned endpoints
            } else {
                // Compound two sines for more organic motion
                let primary = sin(elapsed * frequencies[i] + phases[i])
                let secondary = sin(elapsed * frequencies[i] * 1.7 + phases[i] * 1.3) * 0.4
                yValues[i] = amp * (primary + secondary) * 0.75
            }
        }

        // Ripple events on peak onset
        let delta = raw - previous
        if delta > 0.18 && raw > 0.3 && (now - lastSpawnAt) > 0.1 {
            ripples.append(RippleState(spawnTime: now, direction: -1, initialAmplitude: Double(raw)))
            ripples.append(RippleState(spawnTime: now, direction: 1, initialAmplitude: Double(raw)))
            lastSpawnAt = now
        }
        previous = raw
        ripples.removeAll { $0.isDead(at: now) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reset()
    }

    func reset() {
        smoothed = 0
        intensity = 0
        previous = 0
        yValues = Array(repeating: 0, count: count)
        ripples.removeAll()
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
