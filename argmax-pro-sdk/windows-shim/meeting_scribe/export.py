"""
Transcript model, terminal rendering, and Markdown export. No Argmax logic here,
except for grouping WordWithSpeaker results.
Swift twin: native/Sources/MeetingScribe/TranscriptExport.swift
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

if os.name == "nt":
    os.system("")  # turns on ANSI escape codes in the classic Windows console


@dataclass
class SpeakerLine:
    """One run of text from one speaker."""

    speaker: str | None  # None = no diarization
    start: float | None  # seconds from the start of the session, if known
    text: str

    @property
    def formatted(self) -> str:
        time = f"[{clock(self.start)}] " if self.start is not None else ""
        who = f"Speaker {self.speaker}: " if self.speaker is not None else ""
        return time + who + self.text.strip()

    @staticmethod
    def group(words) -> list[SpeakerLine]:
        """Groups consecutive words from the same speaker into lines (same helper as the docs example)."""
        lines: list[SpeakerLine] = []
        for w in words:
            speaker = str(w.speaker) if w.speaker is not None else "?"
            if lines and lines[-1].speaker == speaker:
                lines[-1].text += w.word_timing.word
            else:
                lines.append(SpeakerLine(speaker=speaker, start=w.word_timing.start, text=w.word_timing.word))
        return lines


class TerminalUI:
    @staticmethod
    def render(confirmed: list[SpeakerLine], hypothesis: str, speaker_count: int | None = None) -> None:
        """Redraws the live view: confirmed lines, then the hypothesis in blue."""
        screen = "\033[2J\033[H"  # clear screen, cursor home
        if speaker_count is not None:
            screen += f"Speakers detected: {speaker_count}\n\n"
        screen += "\n".join(line.formatted for line in confirmed[-20:])
        if hypothesis:
            screen += f"\n\033[34m{hypothesis}\033[0m"
        print(screen, flush=True)


def write_transcript(lines: list[SpeakerLine], title: str, folder: str, base_name: str, language: str | None = None) -> Path:
    md = f"# {title}\n\n"
    md += f"_Transcribed with argmax_shim (dev stand-in for the Argmax Pro SDK) on {datetime.now():%Y-%m-%d %H:%M}"
    if language:
        md += f" · language: {language}"
    md += "_\n\n"
    md += "\n\n".join(line.formatted for line in lines) + "\n"
    return write_raw(md, folder=folder, file_name=f"{base_name}.md")


def write_raw(contents: str, folder: str, file_name: str) -> Path:
    path = Path(folder) / file_name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")
    return path


def clock(seconds: float) -> str:
    return f"{int(seconds) // 60:02d}:{seconds % 60:04.1f}"


def timestamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")
