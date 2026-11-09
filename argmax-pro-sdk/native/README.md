# Meeting Scribe: native (Swift, Argmax Pro SDK)

A macOS command-line app that uses the real Argmax Pro SDK. Everything runs on-device. The network is only used for license checks and model downloads.

## Requirements

- macOS 15+ on Apple Silicon (M1 or newer). Intel Macs are not supported.
- Xcode 16+ / Swift 5.10+
- An Argmax account with two credentials from the [dashboard](https://app.argmaxinc.com):
  - `axst_...` **secret token**: used only to download the SDK from Argmax's package registry.
  - `ax_...` **API key**: unlocks Pro features at runtime.

## Setup

```bash
# 1. One-time registry login. This writes ~/.swiftpm/configuration/registries.json
swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token "$ARGMAX_SECRET_TOKEN"

# 2. Runtime key
export ARGMAX_API_KEY=ax_...

# 3. Build
cd native
swift build -c release
```

If you have the open-source `WhisperKit` package in another project, remove it before adding `argmax-sdk-swift`. The Pro SDK includes it.

The first `live` run asks for microphone access for your terminal app (Terminal, iTerm, VS Code, ...). Allow it in **System Settings → Privacy & Security → Microphone**.

## Usage

```bash
# Live transcription: confirmed text in white, in-progress hypothesis in blue
swift run -c release meeting-scribe live

# Live with speaker labels (Sortformer, up to 8 speakers)
swift run -c release meeting-scribe live --speakers

# Live with custom vocabulary (switches to Parakeet v3 automatically)
swift run -c release meeting-scribe live --speakers --vocab-file ../shared/vocabulary.txt

# Transcribe a file with speakers. Writes transcripts/<name>.md and transcripts/<name>.rttm
swift run -c release meeting-scribe file ~/Downloads/standup.m4a --num-speakers 3

# Pick a different model
swift run -c release meeting-scribe file talk.wav --model parakeet-v2_476MB --no-speakers
```

Press **Ctrl+C** to stop a live session. The transcript is saved to `transcripts/live-<timestamp>.md`.

## Code map

| File | What it shows |
|---|---|
| `Bootstrap.swift` | `ArgmaxSDK.with(ArgmaxConfig(apiKey:))`, `WhisperKitProConfig(model:customVocabularyConfig:)`, `customVocabularyModelState` |
| `LiveCommand.swift` | `LiveTranscriber`, `ArgmaxSource(.device)`, `DecodingOptionsPro`, `StreamTranscriptionMode`, `.confirm`/`.hypothesis`. With `--speakers`: `SpeakerKitPro(SortformerConfig)`, `makeStreamSession(transcriptionSession:diarizationConfig:)`, `.newTranscription`/`.speakerRevision` |
| `FileCommand.swift` | `AudioProcessor.loadAudioAsFloatArray`, `transcribe(audioArray:decodeOptions:)`, language detection, `SpeakerKitDiarizer.pyannote()`, `diarize`, `addSpeakerInfo(.subsegment)`, `generateRTTM` |
| `TranscriptExport.swift` | Grouping `WordWithSpeaker` into lines, terminal rendering, Markdown export (plain Swift) |

## Notes and caveats

- **SDK version.** The install guide pins `3.0.6`, but some doc examples use `2.0.9`. If a signature doesn't match, check the [changelog](https://app.argmaxinc.com/docs/changelog) and the version list (`curl https://api.argmaxinc.com/v1/sdk/argmaxinc/argmax-sdk-swift -H "Authorization: Bearer $ARGMAX_SECRET_TOKEN"`).
- **Untested.** This example was written from the public docs and hasn't been compiled. Most calls are copied from the docs. A few details are inferred and marked `TODO(verify)` (the fields of the speaker segments returned by `addSpeakerInfo`). Some calls may also need `try`/`await` added or removed, depending on SDK version.
- **Custom vocabulary** is disabled for Whisper models, so the app switches to `parakeet-v3_494MB` when you pass a vocabulary. Terms under 4 characters reduce accuracy.
- **Shipping an app?** Don't read the key from an environment variable. Store it obfuscated, or proxy the license server (see the [docs](https://app.argmaxinc.com/docs/guides/proxying-license-server)). On iOS, add `UIBackgroundModes: audio` for background recording.
