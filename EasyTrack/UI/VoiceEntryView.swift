import AVFoundation
import Speech
import SwiftUI

struct VoiceEntryFlow: View {
    @State private var draft: VoiceTransactionDraft?

    var body: some View {
        NavigationStack {
            if let draft {
                TransactionEditor(voiceDraft: draft)
            } else {
                VoiceEntryView { self.draft = $0 }
            }
        }
    }
}

private struct VoiceEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = OfflineSpeechSession()
    @State private var localeID = Locale.current.identifier.lowercased().hasPrefix("it") ? "it-IT" : "en-US"
    @State private var draft: VoiceTransactionDraft?
    let onContinue: (VoiceTransactionDraft) -> Void

    var body: some View {
        Form {
            Section("Offline language") {
                Picker("Language", selection: $localeID) {
                    Text("Italiano").tag("it-IT")
                    Text("English").tag("en-US")
                }.pickerStyle(.segmented)
                Text("EasyTrack starts only when Apple reports on-device recognition for this language. It never falls back to cloud recognition or downloads a model.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Recording") {
                if session.isRecording {
                    Label("Listening on device…", systemImage: "waveform").foregroundStyle(.red)
                    Button("Stop") { session.stop(); interpret() }.buttonStyle(.borderedProminent)
                } else {
                    Button { start() } label: { Label("Start microphone", systemImage: "mic.fill") }
                        .buttonStyle(.borderedProminent)
                }
                Button("Cancel recording", role: .cancel) { session.cancel(); draft = nil }
                    .disabled(!session.isRecording && session.transcript.isEmpty)
                if let error = session.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            }
            Section("Transcript") {
                TextEditor(text: $session.transcript).frame(minHeight: 90)
                Button("Interpret text") { interpret() }.disabled(session.transcript.isEmpty)
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
                    Button("Review in transaction editor") { onContinue(draft) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Voice entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.cancel(); dismiss() } } }
        .onDisappear { session.cancel() }
    }

    private func start() {
        draft = nil
        Task { await session.start(locale: Locale(identifier: localeID)) }
    }

    private func interpret() {
        draft = VoiceEntryParser.parse(session.transcript, locale: Locale(identifier: localeID))
    }
}

@MainActor
private final class OfflineSpeechSession: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(locale: Locale) async {
        cancel()
        errorMessage = nil
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { errorMessage = "Speech recognition permission was denied."; return }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard microphone else { errorMessage = "Microphone permission was denied."; return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            errorMessage = "Offline speech recognition is not installed or available for this language. Continue with typed entry."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in request.append(buffer) }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare(); try audioEngine.start()
            isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self?.stop() }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(20))
                if isRecording { stop() }
            }
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.finish()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        if isRecording { audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0) }
        request?.endAudio(); task?.cancel(); request = nil; task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
