"""
Entry point and shared CLI options.
Swift twin: native/Sources/MeetingScribe/MeetingScribe.swift

    python -m meeting_scribe live [--speakers] [--vocab-file ../shared/vocabulary.txt]
    python -m meeting_scribe file meeting.wav [--num-speakers 3] [--no-speakers]
"""

import argparse
from pathlib import Path

from .bootstrap import Models


def add_common_options(p: argparse.ArgumentParser) -> None:
    """Options shared by `live` and `file` (Swift: CommonOptions)."""
    p.add_argument("--api-key", help="Argmax API key (ax_...). Defaults to ARGMAX_API_KEY. Ignored by the shim.")
    p.add_argument("--model", default=Models.DEFAULT_ASR, help="ASR model name from the Argmax model gallery.")
    p.add_argument("--vocab", help='Comma-separated custom vocabulary, e.g. "Argmax,WhisperKitPro".')
    p.add_argument("--vocab-file", help="File with one vocabulary term per line (see ../shared/vocabulary.txt).")
    p.add_argument("--out", default="transcripts", help="Folder for transcript exports.")


def vocabulary(args: argparse.Namespace) -> list[str]:
    """Merges --vocab and --vocab-file into one list."""
    words = [w.strip() for w in (args.vocab or "").split(",")]
    if args.vocab_file:
        lines = Path(args.vocab_file).read_text(encoding="utf-8").splitlines()
        words += [line.strip() for line in lines if not line.strip().startswith("#")]
    return [w for w in words if w]


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="meeting-scribe",
        description="Meeting transcription with speakers. Windows dev build on argmax_shim (not the real Argmax SDK).",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    live = sub.add_parser("live", help="Transcribe the microphone in real time. Press Ctrl+C to stop and export.")
    add_common_options(live)
    live.add_argument("--speakers", action="store_true", help="Label speakers live with Sortformer (needs the [sortformer] extra).")
    live.add_argument("--mode", default="voiceTriggered", choices=["voiceTriggered", "alwaysOn", "batteryOptimized"])

    file = sub.add_parser("file", help="Transcribe an audio file (wav, m4a, mp3, ...) with speaker labels.")
    add_common_options(file)
    file.add_argument("audio_path", help="Path to the audio file.")
    file.add_argument("--num-speakers", type=int, help="Number of speakers, if known. Improves diarization.")
    file.add_argument("--no-speakers", action="store_true", help="Skip diarization and only transcribe.")

    args = parser.parse_args()
    if args.command == "live":
        from .live import run

        run(args, vocabulary(args))
    else:
        from .file import run

        run(args, vocabulary(args))
