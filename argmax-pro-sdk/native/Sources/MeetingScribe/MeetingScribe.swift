// Entry point and shared CLI options.
// Python twin: windows-shim/meeting_scribe/cli.py

import ArgumentParser
import Foundation

@main
struct MeetingScribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meeting-scribe",
        abstract: "On-device meeting transcription with speakers, built on the Argmax Pro SDK.",
        subcommands: [LiveCommand.self, FileCommand.self]
    )
}

/// Options shared by `live` and `file`.
struct CommonOptions: ParsableArguments {
    @Option(help: "Argmax API key (ax_...). Defaults to the ARGMAX_API_KEY environment variable.")
    var apiKey: String?

    @Option(help: "ASR model name from the Argmax model gallery.")
    var model: String = Models.defaultASR

    @Option(help: "Comma-separated custom vocabulary, e.g. \"Argmax,WhisperKitPro\".")
    var vocab: String?

    @Option(help: "File with one vocabulary term per line (see ../shared/vocabulary.txt).")
    var vocabFile: String?

    @Option(help: "Folder for transcript exports.")
    var out: String = "transcripts"

    /// Merges --vocab and --vocab-file into one list.
    func vocabulary() throws -> [String] {
        var words = (vocab ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let vocabFile {
            let contents = try String(contentsOfFile: vocabFile, encoding: .utf8)
            words += contents
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("#") }
        }
        return words.filter { !$0.isEmpty }
    }
}
