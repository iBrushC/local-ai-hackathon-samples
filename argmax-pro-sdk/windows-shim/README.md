# Meeting Scribe: Windows shim version (Python)

The same app as [`../native`](../native), written against [`argmax_shim`](../../../argmax-windows-shim). That's a **development-only** Python stand-in for the Argmax Pro SDK, so you can build on Windows (or Linux) and port to the real SDK later.

> The shim runs open-source checkpoints (faster-whisper, pyannote.audio, NeMo) on generic runtimes. It's slower and less accurate in real-time mode than the real SDK, and it should never ship. If something works here, it will very likely work better on the real SDK.

## Setup (PowerShell)

```powershell
cd local-ai-hackathon-examples\argmax-pro-sdk\windows-shim
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt     # installs ../../../argmax-windows-shim[light] in editable mode
```

What each feature needs:

| Feature | Command | Extra setup |
|---|---|---|
| Live transcription | `live` | None. Uses Whisper turbo through faster-whisper on native Windows. |
| File transcription + speakers | `file <audio>` | Pyannote is gated. Accept the terms for `pyannote/speaker-diarization-community-1` on Hugging Face, then `$env:HF_TOKEN = "hf_..."`. Install **ffmpeg** on PATH for `.m4a`/`.mp4`. |
| Live speakers | `live --speakers` | `pip install -e "../../../argmax-windows-shim[sortformer]"` (NeMo; **use WSL2**) |
| Custom vocabulary | `--vocab` / `--vocab-file` | `pip install -e "../../../argmax-windows-shim[parakeet]"` (NeMo; **use WSL2**) |

You don't need an API key. The shim accepts and ignores `ARGMAX_API_KEY`, so the code path is the same as native.

## Usage

```powershell
# Live transcription: confirmed text in white, in-progress hypothesis in blue
python -m meeting_scribe live

# Live with speaker labels (Sortformer)
python -m meeting_scribe live --speakers

# Custom vocabulary (switches to Parakeet v3 automatically)
python -m meeting_scribe live --vocab-file ..\shared\vocabulary.txt

# File with speakers. Writes transcripts\<name>.md and transcripts\<name>.rttm
python -m meeting_scribe file C:\path\to\standup.wav --num-speakers 3

# Faster on a CPU laptop
python -m meeting_scribe file talk.wav --model small.en --no-speakers
```

Press **Ctrl+C** once to stop a live session and save the transcript. Press it again to force-quit.

## File-by-file mapping to native

| Python | Swift | Argmax APIs |
|---|---|---|
| `cli.py` | `MeetingScribe.swift` | (CLI only) |
| `bootstrap.py` | `Bootstrap.swift` | `ArgmaxSDK.with_`, `WhisperKitProConfig(custom_vocabulary_config=...)`, `custom_vocabulary_model_state` |
| `live.py` | `LiveCommand.swift` | `LiveTranscriber`, `ArgmaxSource`, `DecodingOptionsPro`, `StreamTranscriptionMode`, `LiveResult.Confirm/Hypothesis`, `SpeakerKitPro(SortformerConfig)`, `make_stream_session` |
| `file.py` | `FileCommand.swift` | `AudioProcessor.load_audio_as_float_array`, `transcribe`, `SpeakerKitDiarizer.pyannote()`, `diarize`, `add_speaker_info`, `generate_rttm` |
| `export.py` | `TranscriptExport.swift` | (plain code) |

## Porting to the real SDK

Every shim call has an `@mirrors(...)` decorator naming its Swift equivalent, and [`MAPPING.md`](../../../argmax-windows-shim/MAPPING.md) lists them all. The main translations used here:

| Shim (Python) | Pro SDK (Swift) |
|---|---|
| `ArgmaxSDK.with_(ArgmaxConfig(api_key=k))` | `await ArgmaxSDK.with(ArgmaxConfig(apiKey: k))` (real key required) |
| `kit.transcribe(audio_array=a, decode_options=o)` | `try await kit.transcribe(audioArray: a, decodeOptions: o)` |
| `live.start_transcription(mic)` + `match LiveResult.Confirm(...)` | `try await live.startTranscription(for: mic)` + `case .confirm(...)` |
| `for r in session.results` | `for try await r in session.results` |
| `TranscribeDiarizeResultType.SPEAKER_REVISION` | `.speakerRevision` |
| `SpeakerInfoStrategy.SUBSEGMENT` | `.subsegment` |

What behaves differently in the shim (from the shim's README):

- **Real-time:** LocalAgreement-2 instead of Argmax's streaming algorithm. It has more lag, and confirmed text can differ from file transcription.
- **Custom vocabulary:** fuzzy text correction instead of audio keyword spotting. Expect lower recall.
- **Live speakers:** re-diarizes the whole buffer every 2 s. Keep demo sessions to a few minutes.
- `batteryOptimized` behaves like `voiceTriggered`, and the license key is ignored.
