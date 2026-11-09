# Argmax Pro SDK example: Meeting Scribe

**Meeting Scribe** is a command-line app for on-device meeting transcription. It shows four features of the [Argmax Pro SDK](https://app.argmaxinc.com/docs):

| Feature | What you see | Argmax APIs |
|---|---|---|
| **Real-time transcription** | Confirmed text plus a live "hypothesis" for the newest words | `LiveTranscriber`, `ArgmaxSource`, `DecodingOptionsPro`, `StreamTranscriptionMode` |
| **Real-time speaker labels** | `Speaker 0: ... / Speaker 1: ...` live, with earlier lines corrected as diarization improves | `SpeakerKitPro` + Sortformer, `makeStreamSession`, `.speakerRevision` |
| **Custom vocabulary** | Product names and jargon spelled correctly (up to 3000 terms) | `WhisperKitProConfig(customVocabularyConfig:)`, `setCustomVocabulary` |
| **File transcription with speakers** | Markdown transcript + RTTM file, with detected language | `transcribe(audioArray:)`, `SpeakerKitDiarizer.pyannote()`, `addSpeakerInfo`, `generateRTTM` |

It's built twice, with the same commands, flags, and file layout:

```
argmax-pro-sdk/
├── native/          Swift + the real Pro SDK. macOS 15+, Apple Silicon, needs an Argmax key
├── windows-shim/    Python + argmax_shim. Windows/Linux dev stand-in, no key needed
└── shared/          vocabulary.txt, .env.example
```

## Which version should I use?

- **On a Mac with an Argmax key:** use [`native/`](native/README.md). It's the real thing, and it's what you'd ship (in an app, not a CLI).
- **On Windows, or without a key yet:** use [`windows-shim/`](windows-shim/README.md) to build and iterate. Then port to native. Each Python file maps 1:1 to a Swift file, and the shim's [`MAPPING.md`](../../argmax-windows-shim/MAPPING.md) gives the Swift name for every call.

The Pro SDK runs on Apple platforms (Swift) and Android (Kotlin). Argmax doesn't plan Windows support, which is why the shim exists.

## Commands (both versions)

```text
meeting-scribe live  [--speakers] [--mode voiceTriggered|alwaysOn|batteryOptimized]
meeting-scribe file  <audio> [--num-speakers N] [--no-speakers]

common: --model <name> --vocab "A,B,C" --vocab-file ../shared/vocabulary.txt --out transcripts --api-key ax_...
```

| | Native | Windows shim |
|---|---|---|
| Run | `swift run -c release meeting-scribe live` | `python -m meeting_scribe live` |
| Key | `ARGMAX_API_KEY=ax_...` (required) | ignored |
| Default ASR | `large-v3-v20240930_626MB` (Whisper turbo) | same, via faster-whisper |
| With a vocabulary | auto-switches to `parakeet-v3_494MB` | same (needs NeMo, so use WSL2) |

## Models used

| Model | Argmax name | Used for |
|---|---|---|
| Whisper large-v3 turbo | `large-v3-v20240930_626MB` | Default transcription, language detection |
| Parakeet v3 | `parakeet-v3_494MB` | Transcription when custom vocabulary is on (Whisper doesn't support it) |
| Sortformer / Nemotron | `SortformerConfig` | Real-time speaker labels (up to 8 speakers) |
| Pyannote Community-1 | `SpeakerKitDiarizer.pyannote()` | Pre-recorded speaker diarization |

## Status

Both versions were written from the public docs and **have not been built or run**. Native needs the private SDK and a key, and the shim needs model downloads. Spots that rely on inferred API details are marked `TODO(verify)`. The docs also disagree on the SDK version (`3.0.6` in the install guide, `2.0.9` in some examples), so check the changelog if a signature doesn't match.

## Ideas to extend it

- Put `LiveCommand` behind a SwiftUI view. The `batches` / `seekTime` revision logic carries over unchanged.
- Transcribe mic + system audio as two streams with `CustomSource` (one `LiveTranscriber`, two `registerStream` calls).
- Add a spoken recap with TTSKit (`.qwen3TTS_0_6b` native, Kokoro in the shim).
- Use `--mode batteryOptimized` and `.batteryOptimized` for all-day capture on a laptop.
