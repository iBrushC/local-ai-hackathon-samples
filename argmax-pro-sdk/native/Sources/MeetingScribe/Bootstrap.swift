// License activation, model selection, and WhisperKitPro setup.
// Python twin: windows-shim/meeting_scribe/bootstrap.py
//
// Docs: https://app.argmaxinc.com/docs/guides/upgrading-to-pro-sdk
//       https://app.argmaxinc.com/docs/examples/custom-vocabulary

import Argmax
import ArgumentParser
import Foundation

enum Models {
    /// Whisper large-v3 turbo: multilingual and accurate, but it doesn't support custom vocabulary.
    static let defaultASR = "large-v3-v20240930_626MB"
    /// Parakeet v3: 25 languages, supports custom vocabulary. Used when the user passes a vocabulary.
    static let vocabularyASR = "parakeet-v3_494MB"

    static func isWhisper(_ name: String) -> Bool {
        name.hasPrefix("large-") || name.hasPrefix("tiny") || name.hasPrefix("base") || name.hasPrefix("small")
    }
}

enum Bootstrap {
    /// Activates the Pro SDK. The key is checked against api.argmaxinc.com on first use,
    /// and a per-device license is cached in the Keychain so later runs work offline.
    static func activateSDK(apiKey: String?) async throws {
        guard let key = apiKey ?? ProcessInfo.processInfo.environment["ARGMAX_API_KEY"], key.hasPrefix("ax_") else {
            throw ValidationError("Set ARGMAX_API_KEY (or pass --api-key) to your ax_ key from https://app.argmaxinc.com")
        }
        await ArgmaxSDK.with(ArgmaxConfig(apiKey: key))
    }

    /// Creates WhisperKitPro and enables custom vocabulary if any terms were given.
    static func makeWhisperKitPro(model requested: String, vocabulary: [String]) async throws -> WhisperKitPro {
        var model = requested
        if !vocabulary.isEmpty && Models.isWhisper(model) {
            // Custom vocabulary is disabled for Whisper models in the Pro SDK.
            print("Custom vocabulary needs a non-Whisper model; switching \(model) -> \(Models.vocabularyASR)")
            model = Models.vocabularyASR
        }

        print("Loading \(model) (first run downloads it)...")
        let config: WhisperKitProConfig
        if vocabulary.isEmpty {
            config = WhisperKitProConfig(model: model)
        } else {
            // Keyword spotting runs alongside ASR and overwrites matching spans of the
            // transcript. Up to 3000 terms. You can change them at runtime with
            // `try whisperKitPro.setCustomVocabulary([...])`.
            config = WhisperKitProConfig(model: model, customVocabularyConfig: .init(words: vocabulary))
        }
        let whisperKitPro = try await WhisperKitPro(config)

        if !vocabulary.isEmpty {
            print("Custom vocabulary (\(vocabulary.count) terms): \(whisperKitPro.customVocabularyModelState)")
        }
        return whisperKitPro
    }
}
