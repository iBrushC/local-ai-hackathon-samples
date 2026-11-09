// Transcript model, terminal rendering, and Markdown export. No Argmax types here,
// except for grouping WordWithSpeaker results.
// Python twin: windows-shim/meeting_scribe/export.py

import Argmax
import Foundation

/// One run of text from one speaker.
struct SpeakerLine {
    var speaker: String?   // nil = no diarization
    var start: Double?     // seconds from the start of the session, if known
    var text: String

    var formatted: String {
        let time = start.map { "[\(TranscriptExport.clock($0))] " } ?? ""
        let who = speaker.map { "Speaker \($0): " } ?? ""
        return time + who + text.trimmingCharacters(in: .whitespaces)
    }

    /// Groups consecutive words from the same speaker into lines (same helper as the docs example).
    static func group(_ words: [WordWithSpeaker], at seekTime: Double) -> [SpeakerLine] {
        var lines: [SpeakerLine] = []
        for word in words {
            let speaker = word.speaker.map { "\($0)" } ?? "?"
            if lines.last?.speaker == speaker {
                lines[lines.count - 1].text += word.wordTiming.word
            } else {
                lines.append(SpeakerLine(speaker: speaker, start: Double(word.wordTiming.start), text: word.wordTiming.word))
            }
        }
        return lines
    }
}

enum TerminalUI {
    /// Redraws the live view: confirmed lines, then the hypothesis in blue.
    static func render(confirmed: [SpeakerLine], hypothesis: String, speakerCount: Int? = nil) {
        var screen = "\u{1B}[2J\u{1B}[H"  // clear screen, cursor home
        if let speakerCount { screen += "Speakers detected: \(speakerCount)\n\n" }
        screen += confirmed.suffix(20).map(\.formatted).joined(separator: "\n")
        if !hypothesis.isEmpty { screen += "\n\u{1B}[34m\(hypothesis)\u{1B}[0m" }
        print(screen)
    }
}

enum TranscriptExport {
    @discardableResult
    static func write(_ lines: [SpeakerLine], title: String, folder: String, baseName: String, language: String? = nil) throws -> URL {
        var md = "# \(title)\n\n"
        md += "_Transcribed on-device with the Argmax Pro SDK on \(Date().formatted())"
        if let language { md += " · language: \(language)" }
        md += "_\n\n"
        md += lines.map(\.formatted).joined(separator: "\n\n") + "\n"
        return try writeRaw(md, folder: folder, fileName: "\(baseName).md")
    }

    static func writeRaw(_ contents: String, folder: String, fileName: String) throws -> URL {
        let dir = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func clock(_ seconds: Double) -> String {
        String(format: "%02d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
