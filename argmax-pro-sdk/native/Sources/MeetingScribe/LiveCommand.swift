// `meeting-scribe live`: real-time transcription from the microphone.
// Python twin: windows-shim/meeting_scribe/live.py
//
// Without --speakers: LiveTranscriber (the high-level API) streams confirmed and hypothesis text.
// With --speakers:    WhisperKitPro stream session + SpeakerKitPro (Sortformer) for live speaker labels.
//
// Docs: https://app.argmaxinc.com/docs/examples/real-time-transcription

import Argmax
import ArgumentParser
import Foundation

struct LiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "live",
        abstract: "Transcribe the microphone in real time. Press Ctrl+C to stop and export."
    )

    @OptionGroup var common: CommonOptions

    @Flag(help: "Label speakers live with Sortformer (up to 8 speakers).")
    var speakers = false

    @Option(help: "Stream mode: voiceTriggered (default, saves compute in silence), alwaysOn, batteryOptimized.")
    var mode: String = "voiceTriggered"

    func run() async throws {
        try await Bootstrap.activateSDK(apiKey: common.apiKey)
        let whisperKitPro = try await Bootstrap.makeWhisperKitPro(model: common.model, vocabulary: try common.vocabulary())

        let options = DecodingOptionsPro(
            base: .init(task: .transcribe, wordTimestamps: true, chunkingStrategy: .vad),
            transcribeInterval: 0.1,
            streamTranscriptionMode: streamMode,
            alignTimestampsToGlobal: true
        )

        let transcript = speakers
            ? try await runWithSpeakers(whisperKitPro, options: options)
            : try await runTranscriptOnly(whisperKitPro, options: options)

        let file = try TranscriptExport.write(transcript, title: "Live session", folder: common.out, baseName: "live-\(TranscriptExport.timestamp())")
        print("\nSaved transcript to \(file.path)")
    }

    private var streamMode: StreamTranscriptionMode {
        switch mode {
        case "alwaysOn": return .alwaysOn
        case "batteryOptimized": return .batteryOptimized
        default: return .voiceTriggered(minProcessInterval: 0.3)
        }
    }

    // MARK: - Transcript only (LiveTranscriber)

    private func runTranscriptOnly(_ whisperKitPro: WhisperKitPro, options: DecodingOptionsPro) async throws -> [SpeakerLine] {
        let liveTranscriber = LiveTranscriber(whisperKit: whisperKitPro)
        let mic = ArgmaxSource(streamType: .device(nil))  // nil = default input device

        try await liveTranscriber.registerStream(streamSource: mic, options: options)
        let results = try await liveTranscriber.startTranscription(for: mic)

        let stopSignal = onCtrlC {
            Task { try? await liveTranscriber.stopAndRemoveStream(for: mic) }
        }
        defer { stopSignal.cancel() }
        print("\nListening... (Ctrl+C to stop)\n")

        var lines: [SpeakerLine] = []
        for try await result in results {
            switch result {
            case .confirm(let text, let seconds, _):
                // Confirmed text is final and won't change.
                lines.append(SpeakerLine(speaker: nil, start: Double(seconds), text: text))
                TerminalUI.render(confirmed: lines, hypothesis: "")
            case .hypothesis(let text, _, _):
                // Hypothesis text is an early guess for the newest audio. It's replaced on the next update.
                TerminalUI.render(confirmed: lines, hypothesis: text)
            @unknown default:
                break
            }
        }
        return lines
    }

    // MARK: - With speakers (SpeakerKitPro + Sortformer)

    private func runWithSpeakers(_ whisperKitPro: WhisperKitPro, options: DecodingOptionsPro) async throws -> [SpeakerLine] {
        print("Loading Sortformer real-time diarization...")
        let speakerKit = try await SpeakerKitPro(SortformerConfig(load: true, streamingConfig: .realtime))

        let transcribeSession = whisperKitPro.makeStreamSession(options: options)
        let combinedSession = speakerKit.makeStreamSession(
            transcriptionSession: transcribeSession,
            diarizationConfig: SortformerDiarizationOptions(sortformerMode: .realtime)
        )

        let (micStream, micContinuation) = whisperKitPro.audioProcessor.startStreamingRecordingLive()
        let stopSignal = onCtrlC { micContinuation.finish() }
        defer { stopSignal.cancel() }

        await combinedSession.start(audioInputStream: micStream)
        print("\nListening with speaker labels... (Ctrl+C to stop)\n")

        // Batches of confirmed words, keyed by seekTime. When Sortformer revises who said
        // what, it emits .speakerRevision with the same seekTime, and that batch is replaced.
        var batches: [(seekTime: Float, lines: [SpeakerLine])] = []

        for try await result in combinedSession.results {
            switch result.type {
            case .newTranscription:
                if !result.confirmedWordsWithSpeakers.isEmpty {
                    batches.append((Float(result.seekTime), SpeakerLine.group(result.confirmedWordsWithSpeakers, at: Double(result.seekTime))))
                }
                let hypothesis = SpeakerLine.group(result.hypothesisWordsWithSpeakers, at: Double(result.seekTime))
                    .map(\.formatted).joined(separator: " ")
                TerminalUI.render(confirmed: batches.flatMap(\.lines), hypothesis: hypothesis, speakerCount: result.speakerCount)
            case .speakerRevision:
                if let index = batches.firstIndex(where: { $0.seekTime == Float(result.seekTime) }) {
                    batches[index].lines = SpeakerLine.group(result.confirmedWordsWithSpeakers, at: Double(result.seekTime))
                }
                TerminalUI.render(confirmed: batches.flatMap(\.lines), hypothesis: "", speakerCount: result.speakerCount)
            @unknown default:
                break
            }
        }
        return batches.flatMap(\.lines)
    }

    /// Runs `handler` once when the user presses Ctrl+C, instead of killing the process.
    /// The stream then ends cleanly and the transcript gets exported.
    private func onCtrlC(_ handler: @escaping @Sendable () -> Void) -> DispatchSourceSignal {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler {
            print("\nStopping...")
            handler()
        }
        source.resume()
        return source
    }
}
