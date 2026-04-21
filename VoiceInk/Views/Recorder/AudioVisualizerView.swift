import SwiftUI

/// ValVoice audio visualizer — a rolling amplitude history rendered as capsule bars.
///
/// Instead of bars that sway on a pure sine wave (the previous design felt fake
/// because the motion was time-driven, not audio-driven), each bar shows a slice
/// of the actual amplitude history. New samples enter on the right, old samples
/// scroll left — an oscilloscope-style waveform that genuinely responds to voice.
struct AudioVisualizer: View {
    let audioMeter: AudioMeter      // current snapshot (re-passed each render)
    let sampler: () -> Float        // called by the buffer on each tick to read live amplitude
    let color: Color
    let isActive: Bool

    private let barCount = 15
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2.5
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 28

    @StateObject private var buffer = AmplitudeBuffer(capacity: 15)

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(isActive ? 0.95 : 0.55))
                    .frame(width: barWidth, height: barHeight(for: index))
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: buffer.samples[index])
            }
        }
        .frame(height: maxHeight)
        .onAppear { buffer.start(sampler: sampler) }
        .onDisappear { buffer.stop() }
        .onChange(of: isActive) { _, active in
            if !active { buffer.resetToSilent() }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Boost low amplitudes so quiet speech still moves the bars visibly
        let sample = CGFloat(max(0, min(1, pow(buffer.samples[index], 0.55))))
        // Center bars slightly taller — gives the visualizer a subtle "focus"
        let centerDist = abs(Double(index) - Double(barCount - 1) / 2) / Double(barCount / 2)
        let weight = 1.0 - centerDist * 0.22
        let raw = minHeight + sample * CGFloat(weight) * (maxHeight - minHeight)
        return max(minHeight, raw)
    }
}

/// Rolling amplitude history. Ticks at 20 Hz, shifting new samples in on the right.
final class AmplitudeBuffer: ObservableObject {
    @Published var samples: [Float]
    private let capacity: Int
    private var timer: Timer?
    private var sampler: (() -> Float)?

    init(capacity: Int) {
        self.capacity = capacity
        self.samples = Array(repeating: 0, count: capacity)
    }

    func start(sampler: @escaping () -> Float) {
        self.sampler = sampler
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let sampler = self.sampler else { return }
            var s = self.samples
            s.removeFirst()
            s.append(max(0, min(1, sampler())))
            self.samples = s
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func resetToSilent() {
        samples = Array(repeating: 0, count: capacity)
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
