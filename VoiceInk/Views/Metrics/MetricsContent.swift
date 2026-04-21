import SwiftUI
import SwiftData
import os

struct MetricsContent: View {
    private let logger = Logger(subsystem: "com.nicolaivalenta.valvoice", category: "MetricsContent")
    let modelContext: ModelContext
    let licenseState: LicenseViewModel.LicenseState

    @State private var totalCount: Int = 0
    @State private var totalWords: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var isLoadingMetrics: Bool = true
    @State private var metricsTask: Task<Void, Never>?

    var body: some View {
        Group {
            if totalCount == 0 && !isLoadingMetrics {
                emptyStateView
            } else if isLoadingMetrics {
                ProgressView("Loading metrics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            heroSection
                            metricsSection

                            Spacer(minLength: 20)
                        }
                        .frame(minHeight: geometry.size.height - 56)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 32)
                    }
                    .background(Color(.windowBackgroundColor))
                }
            }
        }
        .task {
            await loadMetricsEfficiently()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionCreated)) { _ in
            metricsTask?.cancel()
            metricsTask = Task {
                await loadMetricsEfficiently()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionCompleted)) { _ in
            metricsTask?.cancel()
            metricsTask = Task {
                await loadMetricsEfficiently()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionDeleted)) { _ in
            metricsTask?.cancel()
            metricsTask = Task {
                await loadMetricsEfficiently()
            }
        }
        .onDisappear {
            metricsTask?.cancel()
        }
    }
    
    private func loadMetricsEfficiently() async {
        await MainActor.run {
            self.isLoadingMetrics = true
        }

        let modelContainer = modelContext.container

        let backgroundContext = ModelContext(modelContainer)

        do {
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isLoadingMetrics = false
                }
                return
            }

            let completedFilter = #Predicate<Transcription> { $0.transcriptionStatus == "completed" }
            let count = try backgroundContext.fetchCount(FetchDescriptor<Transcription>(predicate: completedFilter))

            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isLoadingMetrics = false
                }
                return
            }

            var descriptor = FetchDescriptor<Transcription>(predicate: completedFilter)
            descriptor.propertiesToFetch = [\.text, \.duration]

            var words = 0
            var duration: TimeInterval = 0

            try backgroundContext.enumerate(descriptor) { transcription in
                words += transcription.text.split(whereSeparator: \.isWhitespace).count
                duration += transcription.duration
            }

            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isLoadingMetrics = false
                }
                return
            }

            await MainActor.run {
                self.totalCount = count
                self.totalWords = words
                self.totalDuration = duration
                self.isLoadingMetrics = false
            }
        } catch {
            logger.error("Error loading metrics: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.isLoadingMetrics = false
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.secondary)
            Text("No Transcriptions Yet")
                .font(.title3.weight(.semibold))
            Text("Start your first recording to unlock value insights.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Sections
    
    private var heroSection: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                
                (Text("You have saved ")
                    .fontWeight(.bold)
                    .foregroundColor(.black.opacity(0.75))
                 +
                 Text(formattedTimeSaved)
                    .fontWeight(.black)
                    .font(.system(size: 36, design: .rounded))
                    .foregroundStyle(.black)
                 +
                 Text(" with ValVoice")
                    .fontWeight(.bold)
                    .foregroundColor(.black.opacity(0.75))
                )
                .font(.system(size: 30))
                .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Text(heroSubtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.black.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 30, x: 0, y: 16)
    }
    
    private var metricsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            MetricCard(
                icon: "mic.fill",
                title: "Sessions Recorded",
                value: "\(totalCount)",
                detail: "ValVoice sessions completed",
                color: .purple
            )

            MetricCard(
                icon: "text.alignleft",
                title: "Words Dictated",
                value: Formatters.formattedNumber(totalWords),
                detail: "words generated",
                color: Color("AccentColor")
            )
            
            MetricCard(
                icon: "speedometer",
                title: "Words Per Minute",
                value: averageWordsPerMinute > 0
                    ? String(format: "%.1f", averageWordsPerMinute)
                    : "–",
                detail: "ValVoice vs. typing by hand",
                color: .yellow
            )
            
            MetricCard(
                icon: "keyboard.fill",
                title: "Keystrokes Saved",
                value: Formatters.formattedNumber(totalKeystrokesSaved),
                detail: "fewer keystrokes",
                color: .orange
            )
        }
    }
    
    private var formattedTimeSaved: String {
        let formatted = Formatters.formattedDuration(timeSaved, style: .full, fallback: "Time savings coming soon")
        return formatted
    }
    
    private var heroSubtitle: String {
        guard totalCount > 0 else {
            return "Your ValVoice journey starts with your first recording."
        }

        let wordsText = Formatters.formattedNumber(totalWords)
        let sessionText = totalCount == 1 ? "session" : "sessions"

        return "Dictated \(wordsText) words across \(totalCount) \(sessionText)."
    }
    
    private var heroGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color("AccentColor"),
                Color("AccentColor").opacity(0.92),
                Color("AccentColor").opacity(0.8)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Computed Metrics

    private var estimatedTypingTime: TimeInterval {
        let averageTypingSpeed: Double = 35 // words per minute
        let estimatedTypingTimeInMinutes = Double(totalWords) / averageTypingSpeed
        return estimatedTypingTimeInMinutes * 60
    }

    private var timeSaved: TimeInterval {
        max(estimatedTypingTime - totalDuration, 0)
    }

    private var averageWordsPerMinute: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(totalWords) / (totalDuration / 60.0)
    }

    private var totalKeystrokesSaved: Int {
        Int(Double(totalWords) * 5.0)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

private enum Formatters {
    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
    static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        return formatter
    }()
    
    static func formattedNumber(_ value: Int) -> String {
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    static func formattedDuration(_ interval: TimeInterval, style: DateComponentsFormatter.UnitsStyle, fallback: String = "–") -> String {
        guard interval > 0 else { return fallback }
        durationFormatter.unitsStyle = style
        durationFormatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        return durationFormatter.string(from: interval) ?? fallback
    }
}

