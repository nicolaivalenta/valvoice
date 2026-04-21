import SwiftUI
import SwiftData

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingSettings = false
    let whisperPrompt: WhisperPrompt

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                mainContent
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .slidingPanel(isPresented: $isShowingSettings, width: 400) {
            DictionarySettingsPanel {
                withAnimation(.smooth(duration: 0.3)) {
                    isShowingSettings = false
                }
            }
        }
    }

    private var heroSection: some View {
        CompactHeroSection(
            icon: "arrow.2.squarepath",
            title: "Word Replacements",
            description: "Automatically replace specific words or phrases with custom formatted text",
            maxDescriptionWidth: 500
        )
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowingSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isShowingSettings ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Dictionary settings")
            }

            WordReplacementView()
                .background(CardBackground(isSelected: false))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
}
