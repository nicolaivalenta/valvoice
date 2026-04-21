import Foundation
import SwiftData
import OSLog

class DictionaryMigrationService {
    static let shared = DictionaryMigrationService()
    private let logger = Logger(subsystem: "com.nicolaivalenta.valvoice", category: "DictionaryMigration")

    private let migrationCompletedKey = "HasMigratedDictionaryToSwiftData_v2"
    private let defaultReplacementsSeededKey = "ValVoice_DefaultReplacementsSeeded_v1"
    private let vocabularyKey = "CustomVocabularyItems"
    private let wordReplacementsKey = "wordReplacements"

    /// Default word replacements shipped with ValVoice.
    /// Each entry: (variants the user might dictate) → (what to paste)
    private let defaultReplacements: [(original: String, replacement: String)] = [
        ("Clawd, Clawed, clawd, clawed", "Claude"),
        ("val voice, Val voice, Val Voice, vowel voice, Vowel voice, Vowel Voice", "ValVoice"),
    ]

    private init() {}

    /// Migrates dictionary data from UserDefaults to SwiftData, then seeds defaults
    /// if they haven't been planted yet. Both operations are one-time.
    func migrateIfNeeded(context: ModelContext) {
        // Seed ValVoice defaults (runs once per install, independent of legacy migration)
        seedDefaultReplacementsIfNeeded(context: context)

        // Check if migration has already been completed
        if UserDefaults.standard.bool(forKey: migrationCompletedKey) {
            logger.info("Dictionary migration already completed, skipping")
            return
        }

        logger.info("Starting dictionary migration from UserDefaults to SwiftData")

        var vocabularyMigrated = 0
        var replacementsMigrated = 0

        // Migrate vocabulary words
        if let data = UserDefaults.standard.data(forKey: vocabularyKey) {
            do {
                // Decode old vocabulary structure
                let decoder = JSONDecoder()
                let oldVocabulary = try decoder.decode([OldVocabularyWord].self, from: data)

                logger.info("Found \(oldVocabulary.count, privacy: .public) vocabulary words to migrate")

                for oldWord in oldVocabulary {
                    let newWord = VocabularyWord(word: oldWord.word)
                    context.insert(newWord)
                    vocabularyMigrated += 1
                }

                logger.info("Successfully migrated \(vocabularyMigrated, privacy: .public) vocabulary words")
            } catch {
                logger.error("Failed to migrate vocabulary words: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.info("No vocabulary words found to migrate")
        }

        // Migrate word replacements
        if let replacements = UserDefaults.standard.dictionary(forKey: wordReplacementsKey) as? [String: String] {
            logger.info("Found \(replacements.count, privacy: .public) word replacements to migrate")

            for (originalText, replacementText) in replacements {
                let wordReplacement = WordReplacement(
                    originalText: originalText,
                    replacementText: replacementText
                )
                context.insert(wordReplacement)
                replacementsMigrated += 1
            }

            logger.info("Successfully migrated \(replacementsMigrated, privacy: .public) word replacements")
        } else {
            logger.info("No word replacements found to migrate")
        }

        // Save the migrated data
        do {
            try context.save()
            logger.info("Successfully saved migrated data to SwiftData")

            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            logger.info("Migration completed successfully")
        } catch {
            logger.error("Failed to save migrated data: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Plants ValVoice's default word replacements on first install.
    /// Only runs once per install; skips any replacement whose originals already exist.
    private func seedDefaultReplacementsIfNeeded(context: ModelContext) {
        if UserDefaults.standard.bool(forKey: defaultReplacementsSeededKey) {
            return
        }

        logger.info("Seeding ValVoice default word replacements")

        // Fetch existing originals (case-insensitive compare) so we don't duplicate
        let existing: [WordReplacement] = (try? context.fetch(FetchDescriptor<WordReplacement>())) ?? []
        let existingOriginals = Set(existing.flatMap { entry in
            entry.originalText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        })

        for (original, replacement) in defaultReplacements {
            let variants = original
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let overlaps = variants.contains { existingOriginals.contains($0) }
            if overlaps {
                logger.info("Default seed '\(original, privacy: .public)' collides with existing entry — skipping")
                continue
            }

            let entry = WordReplacement(originalText: original, replacementText: replacement)
            context.insert(entry)
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: defaultReplacementsSeededKey)
            logger.info("Seeded \(self.defaultReplacements.count, privacy: .public) default word replacements")
        } catch {
            logger.error("Failed to seed default replacements: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// Legacy structure for decoding old vocabulary data
private struct OldVocabularyWord: Decodable {
    let word: String

    private enum CodingKeys: String, CodingKey {
        case id, word, dateAdded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decode(String.self, forKey: .word)
        // Ignore other fields that may exist in old format
        _ = try? container.decodeIfPresent(UUID.self, forKey: .id)
        _ = try? container.decodeIfPresent(Date.self, forKey: .dateAdded)
    }
}
