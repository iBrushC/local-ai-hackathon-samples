// `meeting-scribe file <audio>`: transcribe a recording with speaker labels and export it.
// Python twin: windows-shim/meeting_scribe/file.py
//
// Pipeline: WhisperKitPro (word timestamps, VAD chunking, language detection)
//         + SpeakerKitPro with Pyannote (pre-recorded diarization)
//         -> addSpeakerInfo(.subsegment) -> Markdown transcript + RTTM file
//
// Docs: https://app.argmaxinc.com/docs/examples/file-transcription
//       https://app.argmaxinc.com/docs/examples/speaker-diarization

import Argmax
import ArgumentParser
import Foundation

struct FileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file",
        abstract: "Transcribe an audio file (wav, m4a, mp3, ...) with speaker labels."
    )

    @OptionGroup var common: CommonOptions

    @Argument(help: "Path to the audio file.")
    var audioPath: String

    @Option(help: "Number of speakers, if known. Improves diarization.")
    var numSpeakers: Int?

    @Flag(help: "Skip diarization and only transcribe.")
    var noSpeakers = false

    func run() async throws {
        try await Bootstrap.activateSDK(apiKey: common.apiKey)
        let whisperKitPro = try await Bootstrap.makeWhisperKitPro(model: common.model, vocabulary: try common.vocabulary())
        let baseName = URL(fileURLWithPath: audioPath).deletingPathExtension().lastPathComponent

        // 16 kHz mono float samples, shared by transcription and diarization.
        let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)

        // Word timestamps are needed to align words to speakers.
        // detectLanguage: leave `language` unset and read it back from the result.
        let decodeOptions = DecodingOptions(detectLanguage: true, wordTimestamps: true, chunkingStrategy: .vad)

        print("Transcribing \(audioPath)...")
        let results = try await whisperKitPro.transcribe(audioArray: audioArray, decodeOptions: decodeOptions)
        let merged = WhisperKitProUtils.mergeTranscriptionResults(results)
        print("Detected language: \(merged.language)")

        guard !noSpeakers else {
            let lines = [SpeakerLine(speaker: nil, start: 0, text: merged.text)]
            let file = try TranscriptExport.write(lines, title: baseName, folder: common.out, baseName: baseName, language: merged.language)
            print(merged.text)
            print("\nSaved transcript to \(file.path)")
            return
        }

        // Pyannote is the pre-recorded diarizer (Community-1). Sortformer is the real-time one.
        print("Diarizing with Pyannote...")
        let diarizer = SpeakerKitDiarizer.pyannote()
        try await diarizer.downloadModels()
        try await diarizer.loadModels()
        let speakerKit = try await SpeakerKitPro(PyannoteConfig(diarizer: diarizer))

        let options: (any DiarizationOptions)? = numSpeakers.map { PyannoteDiarizationOptions(numberOfSpeakers: $0) }
        let diarization = try await speakerKit.diarize(audioArray: audioArray, options: options)
        print("Found \(diarization.speakerCount) speaker(s)")

        // .subsegment splits transcript segments wherever the speaker changes mid-segment.
        let speakerSegments = diarization.addSpeakerInfo(to: [merged], strategy: .subsegment)
        let lines = speakerSegments.flatMap { $0 }.map { segment in
            // TODO(verify): field names of the SpeakerSegment returned by addSpeakerInfo.
            SpeakerLine(speaker: "\(segment.speaker)", start: nil, text: segment.text)
        }
        for line in lines { print(line.formatted) }

        // Export a readable transcript, plus RTTM (standard diarization format) for evaluation tools.
        let file = try TranscriptExport.write(lines, title: baseName, folder: common.out, baseName: baseName, language: merged.language)
        let rttm = SpeakerKit.generateRTTM(from: diarization, fileName: baseName)
        let rttmFile = try TranscriptExport.writeRaw(rttm.map { "\($0)" }.joined(separator: "\n"), folder: common.out, fileName: "\(baseName).rttm")
        print("\nSaved transcript to \(file.path)\nSaved RTTM to \(rttmFile.path)")
    }
}
