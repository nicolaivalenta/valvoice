// ValVoice history view — fixed two-pane layout.
// Left: list of past transcriptions (selectable, searchable).
// Right: full text of the selected entry with copy-to-clipboard, plus an audio
// player if a recording is available.
// No metadata, no collapsible sidebars — two fixed panes, that's it.

import SwiftUI
import SwiftData
import AVFoundation

struct TranscriptionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcription.timestamp, order: .reverse) private var transcriptions: [Transcription]

    @State private var searchText = ""
    @State private var selectedID: UUID?

    private var filtered: [Transcription] {
        guard !searchText.isEmpty else { return transcriptions }
        let q = searchText.lowercased()
        return transcriptions.filter { t in
            t.text.lowercased().contains(q) ||
            (t.enhancedText?.lowercased().contains(q) ?? false)
        }
    }

    private var selected: Transcription? {
        filtered.first { $0.id == selectedID } ?? filtered.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .frame(width: 320)
                .background(Color(NSColor.textBackgroundColor).opacity(0.2))

            Divider()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedID == nil { selectedID = filtered.first?.id }
        }
    }

    // MARK: - List pane

    private var listPane: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if filtered.isEmpty {
                emptyListState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { t in
                            listRow(for: t)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var emptyListState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
            Text(searchText.isEmpty ? "No transcriptions yet" : "No matches")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func listRow(for t: Transcription) -> some View {
        let text = t.enhancedText?.isEmpty == false ? (t.enhancedText ?? t.text) : t.text
        let isSelected = selectedID == t.id

        return Button {
            selectedID = t.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(relativeTime(t.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color("AccentColor").opacity(0.22) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Detail pane

    private var detailPane: some View {
        Group {
            if let t = selected {
                DetailPane(transcription: t, modelContext: modelContext)
                    .id(t.id) // force-recreate when selection changes so audio player resets
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Select a transcription")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Detail pane (single transcription)

private struct DetailPane: View {
    let transcription: Transcription
    let modelContext: ModelContext

    @State private var justCopied = false
    @StateObject private var audio = AudioPlayback()

    private var displayText: String {
        transcription.enhancedText?.isEmpty == false ? (transcription.enhancedText ?? transcription.text) : transcription.text
    }

    private var audioURL: URL? {
        guard let s = transcription.audioFileURL, let url = URL(string: s),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(role: .destructive) {
                    modelContext.delete(transcription)
                    try? modelContext.save()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView {
                Text(displayText)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 14) {
                // Copy button (yellow pill, black text)
                Button {
                    copy()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        Text(justCopied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color("AccentColor"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Play/pause button
                if let url = audioURL {
                    Button {
                        audio.toggle(url: url)
                    } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 32, height: 32)
                            .background(Color("AccentColor"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(audio.isPlaying ? "Pause" : "Play audio")
                } else {
                    Text("No audio")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onDisappear { audio.stop() }
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(displayText, forType: .string)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            justCopied = false
        }
    }
}

/// Minimal AVAudioPlayer wrapper — no AVKit/SwiftUI-VideoPlayer involved.
private final class AudioPlayback: ObservableObject {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?
    private var currentURL: URL?

    func toggle(url: URL) {
        if let p = player, currentURL == url {
            if p.isPlaying {
                p.pause()
                isPlaying = false
            } else {
                p.play()
                isPlaying = true
            }
            return
        }
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
            currentURL = url
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentURL = nil
        isPlaying = false
    }
}
