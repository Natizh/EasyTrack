import AVFoundation
import Speech
import SwiftUI

struct VoiceEntryFlow: View {
    @State private var draft: VoiceTransactionDraft?
    var body: some View {
        NavigationStack {
            if let draft { TransactionEditor(voiceDraft: draft) }
            else { VoiceEntryView { self.draft = $0 } }
        }
    }
}

private struct VoiceEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = OfflineSpeechSession()
    @AppStorage("EasyTrack.voiceEntryLanguage") private var storedLanguage = VoiceEntryLanguage.italian.rawValue
    @State private var draft: VoiceTransactionDraft?
    let onContinue: (VoiceTransactionDraft) -> Void

    private var language: VoiceEntryLanguage { VoiceEntryLanguage.restored(storedLanguage) }
    private var languageSelection: Binding<VoiceEntryLanguage> {
        Binding(get: { language }, set: { selected in
            session.cancel(clearTranscript: false)
            storedLanguage = selected.rawValue
            draft = nil
        })
    }

    var body: some View {
        Form {
            Section("Offline language") {
                Picker("Language", selection: languageSelection) {
                    ForEach(VoiceEntryLanguage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(session.isRecording || session.isFinalizing)
                LabeledContent("Active language", value: language.title)
                    .accessibilityIdentifier("voiceActiveLanguage")
                Text("The keyboard language does not select speech recognition. EasyTrack uses the language shown above for both Apple Speech and interpretation.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Recognition starts only when Apple reports this language as available on device. EasyTrack never switches languages, falls back to cloud recognition, or downloads a model.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Recording") {
                if session.isRecording || session.isFinalizing {
                    Label(session.isFinalizing ? "Finishing transcription…" : "Listening on device…",
                          systemImage: session.isFinalizing ? "ellipsis.bubble" : "waveform")
                        .foregroundStyle(.red)
                    Button("Stop") { finishAndInterpret() }
                        .buttonStyle(.borderedProminent).disabled(session.isFinalizing)
                } else {
                    Button { start() } label: { Label("Start microphone", systemImage: "mic.fill") }
                        .buttonStyle(.borderedProminent)
                }
                Button("Cancel recording", role: .cancel) {
                    session.cancel(clearTranscript: false); draft = nil
                }
                .disabled(!session.isRecording && !session.isFinalizing && session.transcript.isEmpty)
                if let error = session.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
            Section("Transcript") {
                TextEditor(text: $session.transcript).frame(minHeight: 90)
                    .accessibilityIdentifier("voiceTranscriptEditor")
                Button("Interpret text") { interpret(session.transcript, locale: language.locale) }
                    .disabled(session.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              session.isRecording || session.isFinalizing)
            }
            if let draft {
                Section("Editable draft") {
                    LabeledContent("Type", value: draft.kind?.title ?? "Review manually")
                    LabeledContent("Amount", value: draft.amountMinor.flatMap { amount in
                        draft.currency.map { Money.format(amount, currency: $0) }
                    } ?? "Missing")
                    LabeledContent("Description", value: draft.merchant ?? "Missing")
                    LabeledContent("Date", value: draft.occurredAt?.formatted(date: .abbreviated, time: .omitted) ?? "Today / review")
                    ForEach(draft.issues, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                    Button("Review in transaction editor") { onContinue(draft) }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Voice entry").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { session.cancel(clearTranscript: false); dismiss() }
        } }
        .onDisappear { session.cancel(clearTranscript: false) }
    }

    private func start() { draft = nil; Task { await session.start(language: language) } }

    private func finishAndInterpret() {
        Task {
            guard let result = await session.stopAndFinalize() else { return }
            interpret(result.text, locale: VoiceEntryLanguage.restored(result.localeID).locale)
        }
    }

    private func interpret(_ text: String, locale: Locale) {
        draft = VoiceEntryParser.parse(text, locale: locale)
    }
}

private struct FinalizedVoiceTranscript {
    let text: String
    let localeID: String
}

@MainActor
private final class OfflineSpeechSession: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var isFinalizing = false
    @Published var errorMessage: String?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var gate = VoiceSessionTokenGate()
    private var activeLanguage: VoiceEntryLanguage?
    private var timeoutTask: Task<Void, Never>?
    private var finalizeTimeoutTask: Task<Void, Never>?
    private var finalization: (token: Int, continuation: CheckedContinuation<FinalizedVoiceTranscript?, Never>)?
    private var tapInstalled = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
            Task { @MainActor in self?.handleInterruption() }
        }
    }

    deinit { if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) } }

    func start(language: VoiceEntryLanguage) async {
        cancel(clearTranscript: true)
        errorMessage = nil
        let token = gate.begin()
        activeLanguage = language
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard gate.accepts(token) else { return }
        guard speech == .authorized else {
            failStart(token, "Speech recognition permission was denied. You can type the transcript manually."); return
        }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard gate.accepts(token) else { return }
        guard microphone else {
            failStart(token, "Microphone permission was denied. You can type the transcript manually."); return
        }
        guard let recognizer = SFSpeechRecognizer(locale: language.locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            failStart(token, "Offline \(language.title) speech recognition is not installed or available. No English or cloud fallback was used; type the transcript manually."); return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request
        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare(); try audioEngine.start()
            guard gate.accepts(token) else { stopAudioInput(endRequest: false); return }
            isRecording = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in self?.handleRecognition(result: result, error: error, token: token) }
            }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await self?.handleRecordingTimeout(token: token)
            }
        } catch {
            stopAudioInput(endRequest: false)
            failStart(token, "Microphone recording could not start: \(error.localizedDescription). You can type the transcript manually.")
        }
    }

    func stopAndFinalize() async -> FinalizedVoiceTranscript? {
        guard let token = gate.activeGeneration, isRecording, let language = activeLanguage else { return nil }
        timeoutTask?.cancel(); stopAudioInput(endRequest: false)
        isRecording = false; isFinalizing = true
        return await withCheckedContinuation { continuation in
            finalization = (token, continuation)
            request?.endAudio()
            finalizeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1_500))
                guard !Task.isCancelled else { return }
                self?.completeFinalization(token: token, language: language,
                    message: "Final speech result was not available in time. The best transcript is preserved for review.")
            }
        }
    }

    func cancel(clearTranscript: Bool) {
        timeoutTask?.cancel(); finalizeTimeoutTask?.cancel()
        stopAudioInput(endRequest: true); recognitionTask?.cancel()
        recognitionTask = nil; request = nil
        if let finalization { finalization.continuation.resume(returning: nil) }
        finalization = nil; gate.cancel(); activeLanguage = nil
        isRecording = false; isFinalizing = false
        if clearTranscript { transcript = "" }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?, token: Int) {
        guard gate.accepts(token) else { return }
        if let result { transcript = result.bestTranscription.formattedString }
        if result?.isFinal == true { completeFinalization(token: token, language: activeLanguage, message: nil) }
        else if let error {
            completeFinalization(token: token, language: activeLanguage,
                message: transcript.isEmpty ? "Speech recognition ended: \(error.localizedDescription). Type the transcript manually." :
                    "Speech recognition ended early. The best transcript is preserved for review.")
        }
    }

    private func completeFinalization(token: Int, language: VoiceEntryLanguage?, message: String?) {
        guard gate.accepts(token), let language else { return }
        timeoutTask?.cancel(); finalizeTimeoutTask?.cancel(); stopAudioInput(endRequest: true)
        recognitionTask?.finish(); recognitionTask = nil; request = nil
        _ = gate.finish(token); activeLanguage = nil
        isRecording = false; isFinalizing = false
        if let message { errorMessage = message }
        let result = FinalizedVoiceTranscript(text: transcript, localeID: language.rawValue)
        if let finalization, finalization.token == token {
            self.finalization = nil; finalization.continuation.resume(returning: result)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleRecordingTimeout(token: Int) async {
        guard gate.accepts(token), isRecording else { return }
        errorMessage = "The 20-second limit was reached. Finishing the best available transcript for review."
        _ = await stopAndFinalize()
    }

    private func handleInterruption() {
        guard gate.activeGeneration != nil else { return }
        cancel(clearTranscript: false)
        errorMessage = "Recording was interrupted. The current transcript is preserved; restart when ready."
    }

    private func failStart(_ token: Int, _ message: String) {
        guard gate.finish(token) else { return }
        activeLanguage = nil; errorMessage = message
        isRecording = false; isFinalizing = false
    }

    private func stopAudioInput(endRequest: Bool) {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if endRequest { request?.endAudio() }
    }
}
