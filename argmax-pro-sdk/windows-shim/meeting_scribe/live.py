"""
`meeting-scribe live`: real-time transcription from the microphone.
Swift twin: native/Sources/MeetingScribe/LiveCommand.swift

Without --speakers: LiveTranscriber (the high-level API) streams confirmed and hypothesis text.
With --speakers:    WhisperKitPro stream session + SpeakerKitPro (Sortformer) for live speaker labels.

Docs: https://app.argmaxinc.com/docs/examples/real-time-transcription
"""

import argparse
import signal
import threading

from argmax_shim.argmax import (
    ArgmaxSource,
    ChunkingStrategy,
    DecodingOptions,
    DecodingOptionsPro,
    DecodingTask,
    LiveResult,
    LiveTranscriber,
    SortformerConfig,
    SortformerDiarizationOptions,
    SortformerMode,
    SortformerStreamingConfig,
    SpeakerKitPro,
    StreamTranscriptionMode,
    StreamType,
    TranscribeDiarizeResultType,
    WhisperKitPro,
)

from . import bootstrap
from .export import SpeakerLine, TerminalUI, timestamp, write_transcript


def run(args: argparse.Namespace, vocabulary: list[str]) -> None:
    bootstrap.activate_sdk(args.api_key)
    whisper_kit_pro = bootstrap.make_whisper_kit_pro(args.model, vocabulary)

    options = DecodingOptionsPro(
        base=DecodingOptions(task=DecodingTask.TRANSCRIBE, word_timestamps=True, chunking_strategy=ChunkingStrategy.VAD),
        transcribe_interval=0.1,
        stream_transcription_mode=_stream_mode(args.mode),
        align_timestamps_to_global=True,
    )

    if args.speakers:
        lines = _run_with_speakers(whisper_kit_pro, options)
    else:
        lines = _run_transcript_only(whisper_kit_pro, options)

    path = write_transcript(lines, title="Live session", folder=args.out, base_name=f"live-{timestamp()}")
    print(f"\nSaved transcript to {path}")


def _stream_mode(mode: str) -> StreamTranscriptionMode:
    if mode == "alwaysOn":
        return StreamTranscriptionMode.always_on()
    if mode == "batteryOptimized":
        return StreamTranscriptionMode.battery_optimized()  # shim: same as voice_triggered
    return StreamTranscriptionMode.voice_triggered(min_process_interval=0.3)


# ---- Transcript only (LiveTranscriber) ------------------------------------------


def _run_transcript_only(whisper_kit_pro: WhisperKitPro, options: DecodingOptionsPro) -> list[SpeakerLine]:
    live_transcriber = LiveTranscriber(whisper_kit_pro)
    mic = ArgmaxSource(stream_type=StreamType.device())  # None = default input device

    live_transcriber.register_stream(stream_source=mic, options=options)
    results = live_transcriber.start_transcription(mic)

    _on_ctrl_c(lambda: threading.Thread(target=live_transcriber.stop_and_remove_stream, args=(mic,)).start())
    print("\nListening... (Ctrl+C to stop)\n")

    lines: list[SpeakerLine] = []
    for result in results:
        match result:
            case LiveResult.Confirm(text, seconds, _):
                # Confirmed text is final and won't change.
                lines.append(SpeakerLine(speaker=None, start=seconds, text=text))
                TerminalUI.render(lines, hypothesis="")
            case LiveResult.Hypothesis(text, _, _):
                # Hypothesis text is an early guess for the newest audio. It's replaced on the next update.
                TerminalUI.render(lines, hypothesis=text)
    return lines


# ---- With speakers (SpeakerKitPro + Sortformer) ----------------------------------


def _run_with_speakers(whisper_kit_pro: WhisperKitPro, options: DecodingOptionsPro) -> list[SpeakerLine]:
    print("Loading Sortformer real-time diarization...")
    # Shim: needs the [sortformer] extra (NeMo). Run it under WSL2 on Windows.
    speaker_kit = SpeakerKitPro(SortformerConfig(load=True, streaming_config=SortformerStreamingConfig.REALTIME))

    transcribe_session = whisper_kit_pro.make_stream_session(options=options)
    combined_session = speaker_kit.make_stream_session(
        transcription_session=transcribe_session,
        diarization_config=SortformerDiarizationOptions(sortformer_mode=SortformerMode.REALTIME),
    )

    mic_stream, mic_continuation = whisper_kit_pro.audio_processor.start_streaming_recording_live()
    _on_ctrl_c(mic_continuation.finish)

    combined_session.start(mic_stream)
    print("\nListening with speaker labels... (Ctrl+C to stop)\n")

    # Batches of confirmed words, keyed by seek_time. When Sortformer revises who said
    # what, it emits SPEAKER_REVISION with the same seek_time, and that batch is replaced.
    batches: list[tuple[float, list[SpeakerLine]]] = []

    def all_lines() -> list[SpeakerLine]:
        return [line for _, batch in batches for line in batch]

    for result in combined_session.results:
        if result.type is TranscribeDiarizeResultType.NEW_TRANSCRIPTION:
            if result.confirmed_words_with_speakers:
                batches.append((result.seek_time, SpeakerLine.group(result.confirmed_words_with_speakers)))
            hypothesis = " ".join(line.formatted for line in SpeakerLine.group(result.hypothesis_words_with_speakers))
            TerminalUI.render(all_lines(), hypothesis=hypothesis, speaker_count=result.speaker_count)
        elif result.type is TranscribeDiarizeResultType.SPEAKER_REVISION:
            for i, (seek_time, _) in enumerate(batches):
                if seek_time == result.seek_time:
                    batches[i] = (seek_time, SpeakerLine.group(result.confirmed_words_with_speakers))
                    break
            TerminalUI.render(all_lines(), hypothesis="", speaker_count=result.speaker_count)
    return all_lines()


def _on_ctrl_c(handler) -> None:
    """Runs `handler` on the first Ctrl+C instead of killing the process.
    The stream then ends cleanly and the transcript gets exported."""

    def _handle(*_):
        print("\nStopping...")
        signal.signal(signal.SIGINT, signal.SIG_DFL)  # a second Ctrl+C force-quits
        handler()

    signal.signal(signal.SIGINT, _handle)
