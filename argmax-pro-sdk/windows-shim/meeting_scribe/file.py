"""
`meeting-scribe file <audio>`: transcribe a recording with speaker labels and export it.
Swift twin: native/Sources/MeetingScribe/FileCommand.swift

Pipeline: WhisperKitPro (word timestamps, VAD chunking, language detection)
        + SpeakerKitPro with Pyannote (pre-recorded diarization)
        -> add_speaker_info(SUBSEGMENT) -> Markdown transcript + RTTM file

Docs: https://app.argmaxinc.com/docs/examples/file-transcription
      https://app.argmaxinc.com/docs/examples/speaker-diarization
"""

import argparse
from pathlib import Path

from argmax_shim.argmax import (
    AudioProcessor,
    ChunkingStrategy,
    DecodingOptions,
    PyannoteConfig,
    PyannoteDiarizationOptions,
    SpeakerInfoStrategy,
    SpeakerKit,
    SpeakerKitDiarizer,
    SpeakerKitPro,
    WhisperKitProUtils,
)

from . import bootstrap
from .export import SpeakerLine, write_raw, write_transcript


def run(args: argparse.Namespace, vocabulary: list[str]) -> None:
    bootstrap.activate_sdk(args.api_key)
    whisper_kit_pro = bootstrap.make_whisper_kit_pro(args.model, vocabulary)
    base_name = Path(args.audio_path).stem

    # 16 kHz mono float samples, shared by transcription and diarization.
    # Shim: .m4a/.mp4 need ffmpeg on PATH. wav/flac/ogg/mp3 work without it.
    audio_array = AudioProcessor.load_audio_as_float_array(args.audio_path)

    # Word timestamps are needed to align words to speakers.
    # detect_language: leave `language` unset and read it back from the result.
    decode_options = DecodingOptions(detect_language=True, word_timestamps=True, chunking_strategy=ChunkingStrategy.VAD)

    print(f"Transcribing {args.audio_path}...")
    results = whisper_kit_pro.transcribe(audio_array=audio_array, decode_options=decode_options)
    merged = WhisperKitProUtils.merge_transcription_results(results)
    print(f"Detected language: {merged.language}")

    if args.no_speakers:
        lines = [SpeakerLine(speaker=None, start=0.0, text=merged.text)]
        path = write_transcript(lines, title=base_name, folder=args.out, base_name=base_name, language=merged.language)
        print(merged.text)
        print(f"\nSaved transcript to {path}")
        return

    # Pyannote is the pre-recorded diarizer (Community-1). Sortformer is the real-time one.
    # Shim: Pyannote is gated. Accept its terms on Hugging Face and set HF_TOKEN.
    print("Diarizing with Pyannote...")
    diarizer = SpeakerKitDiarizer.pyannote()
    diarizer.download_models()
    diarizer.load_models()
    speaker_kit = SpeakerKitPro(PyannoteConfig(diarizer=diarizer))

    options = PyannoteDiarizationOptions(number_of_speakers=args.num_speakers) if args.num_speakers else None
    diarization = speaker_kit.diarize(audio_array, options)
    print(f"Found {diarization.speaker_count} speaker(s)")

    # SUBSEGMENT splits transcript segments wherever the speaker changes mid-segment.
    speaker_segments = diarization.add_speaker_info(to=[merged], strategy=SpeakerInfoStrategy.SUBSEGMENT)
    lines = [
        SpeakerLine(speaker=str(seg.speaker) if seg.speaker is not None else "?", start=seg.start, text=seg.text)
        for segments in speaker_segments
        for seg in segments
    ]
    for line in lines:
        print(line.formatted)

    # Export a readable transcript, plus RTTM (standard diarization format) for evaluation tools.
    path = write_transcript(lines, title=base_name, folder=args.out, base_name=base_name, language=merged.language)
    rttm = SpeakerKit.generate_rttm(diarization, file_name=base_name)
    rttm_path = write_raw("\n".join(str(line) for line in rttm), folder=args.out, file_name=f"{base_name}.rttm")
    print(f"\nSaved transcript to {path}\nSaved RTTM to {rttm_path}")
