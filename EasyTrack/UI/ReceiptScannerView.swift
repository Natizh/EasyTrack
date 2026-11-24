import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import Vision

struct ReceiptCaptureFlow: View {
    @State private var draft: ReceiptTransactionDraft?

    var body: some View {
        NavigationStack {
            if let draft {
                TransactionEditor(receiptDraft: draft)
            } else {
                ReceiptScannerView { self.draft = $0 }
            }
        }
    }
}

private struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.easyTrackTheme) private var theme
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var processing = false
    @State private var statusMessage: String?
    @State private var extraction: ReceiptExtraction?
    @State private var merchant = ""
    @State private var occurredAt = Date()
    @State private var dateWasDetected = false
    @State private var selectedAmountID: String?
    @State private var amountText = ""
    @State private var currency = "EUR"
    let onContinue: (ReceiptTransactionDraft) -> Void

    private var parsedAmount: Int64? {
        guard let value = Money.parseMinor(amountText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.largeTitle).foregroundStyle(theme.accent)
                    Text("Scan one receipt").font(.title2.bold())
                    Text("Vision reads the image on this iPhone. EasyTrack keeps no receipt attachment and creates no transaction until you review and save in the editor.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if extraction == nil {
                Section("Choose an image") {
                    Button { requestCamera() } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                    .disabled(processing)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose existing image", systemImage: "photo.on.rectangle")
                    }
                    .disabled(processing)
                    Button("Continue with manual entry") { continueManually() }
                    if processing { ProgressView("Reading receipt on device…") }
                    if let statusMessage {
                        Text(AppLanguage.localized(statusMessage)).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("receiptScannerStatus")
                    }
                }
            }

            if let extraction {
                Section("Review suggestions") {
                    TextField("Merchant", text: $merchant)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("receiptMerchantField")
                    if extraction.merchantCandidates.count > 1 {
                        Menu("Other merchant candidates") {
                            ForEach(extraction.merchantCandidates, id: \.self) { candidate in
                                Button(candidate) { merchant = candidate }
                            }
                        }
                    }
                    DatePicker("Purchase date", selection: $occurredAt, displayedComponents: .date)
                    Text(AppLanguage.localized(dateWasDetected ? "Date suggested by OCR; verify it." :
                            "No date was recognized. Today is only a manual default—correct it before saving."))
                        .font(.footnote).foregroundStyle(dateWasDetected ? Color.secondary : Color.orange)
                }

                Section("Paid total") {
                    if extraction.amountCandidates.isEmpty {
                        Label("No final total was recognized. Enter it manually.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    } else {
                        if extraction.recommendedAmountID == nil && extraction.amountCandidates.count > 1 {
                            Label("Several amounts are plausible. Choose one candidate or type the paid total.",
                                  systemImage: "questionmark.circle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        ForEach(extraction.amountCandidates) { candidate in
                            Button { select(candidate) } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: selectedAmountID == candidate.id ?
                                          "largecircle.fill.circle" : "circle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(Money.format(candidate.amountMinor, currency: candidate.currency))
                                            .font(.headline)
                                        Text(candidate.sourceText).font(.caption).foregroundStyle(.secondary)
                                        Text(AppLanguage.localized(candidate.finalTotalEvidence ? "Final-total wording found" : "Unverified amount"))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(selectedAmountID == candidate.id ? "Selected" : "Not selected")
                        }
                    }
                    LabeledContent("Amount") {
                        TextField("0,00", text: $amountText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: amountText) { _, _ in selectedAmountID = nil }
                    }
                    Picker("Currency", selection: $currency) {
                        Text("EUR").tag("EUR")
                        Text("USD").tag("USD")
                        Text("GBP").tag("GBP")
                    }
                    if currency != "EUR" {
                        Text("EasyTrack will not treat this as EUR. The existing transaction editor requires a manually verified EUR amount; the detected original amount is shown only as a warning.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Review in transaction editor") { continueToEditor() }
                        .buttonStyle(.borderedProminent)
                        .disabled(parsedAmount == nil)
                        .accessibilityIdentifier("receiptReviewTransaction")
                    Button("Scan another image") { reset() }
                } footer: {
                    Text("The editor requires an explicit Save. Cancelling it creates no transaction. The selected or captured image is released after this step.")
                }
            }
        }
        .navigationTitle("Receipt OCR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .sheet(isPresented: $showingCamera) {
            ReceiptCameraPicker { image in
                showingCamera = false
                if let image { process(image) }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            processing = true
            statusMessage = nil
            Task {
                defer { photoItem = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), data.count <= 25_000_000,
                          let image = UIImage(data: data) else {
                        statusMessage = "The selected image could not be opened or exceeds 25 MB."
                        processing = false
                        return
                    }
                    process(image)
                } catch {
                    statusMessage = error.localizedDescription
                    processing = false
                }
            }
        }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            statusMessage = "Camera is unavailable. Choose an image or continue manually."
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showingCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { showingCamera = true }
                else { statusMessage = "Camera permission was denied. Choose an image or continue manually." }
            }
        case .denied, .restricted:
            statusMessage = "Camera permission is unavailable. Choose an image or continue manually."
        @unknown default:
            statusMessage = "Camera is unavailable. Choose an image or continue manually."
        }
    }

    private func process(_ image: UIImage) {
        processing = true
        statusMessage = nil
        Task {
            do {
                let result = try await ReceiptVisionService.extract(from: image)
                apply(result)
                statusMessage = result.amountCandidates.isEmpty ?
                    "OCR finished, but no total was found. Continue with manual correction." : "OCR finished. Review every suggestion."
            } catch { statusMessage = error.localizedDescription }
            processing = false
        }
    }

    private func apply(_ result: ReceiptExtraction) {
        extraction = result
        merchant = result.merchantCandidates.first ?? ""
        if let date = result.dateCandidates.first {
            occurredAt = date.date
            dateWasDetected = true
        } else {
            occurredAt = .now
            dateWasDetected = false
        }
        if let id = result.recommendedAmountID,
           let candidate = result.amountCandidates.first(where: { $0.id == id }) {
            selectedAmountID = id
            amountText = Money.editString(candidate.amountMinor)
            currency = candidate.currency
        } else {
            selectedAmountID = nil
            amountText = ""
            currency = result.amountCandidates.first?.currency ?? "EUR"
        }
    }

    private func select(_ candidate: ReceiptAmountCandidate) {
        selectedAmountID = candidate.id
        amountText = Money.editString(candidate.amountMinor)
        currency = candidate.currency
    }

    private func continueToEditor() {
        guard let parsedAmount else { return }
        onContinue(ReceiptTransactionDraft(merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
                                           occurredAt: occurredAt, amountMinor: parsedAmount,
                                           currency: currency, dateWasDetected: dateWasDetected))
    }

    private func continueManually() {
        onContinue(ReceiptTransactionDraft(merchant: "", occurredAt: .now, amountMinor: nil,
                                           currency: "EUR", dateWasDetected: false))
    }

    private func reset() {
        extraction = nil
        merchant = ""
        occurredAt = .now
        dateWasDetected = false
        selectedAmountID = nil
        amountText = ""
        currency = "EUR"
        statusMessage = nil
    }
}

private enum ReceiptVisionError: LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The receipt image could not be decoded."
        case .noText: "No readable text was found. Try another image or continue manually."
        }
    }
}

private enum ReceiptVisionService {
    static func extract(from image: UIImage) async throws -> ReceiptExtraction {
        guard let cgImage = image.cgImage else { throw ReceiptVisionError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["it-IT", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            let observations = request.results ?? []
            let sorted = observations.sorted {
                if abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.015 {
                    return $0.boundingBox.maxY > $1.boundingBox.maxY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            let lines = sorted.compactMap { observation -> ReceiptOCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return ReceiptOCRLine(text: candidate.string, confidence: Double(candidate.confidence))
            }
            guard !lines.isEmpty else { throw ReceiptVisionError.noText }
            return ReceiptOCRParser.extract(lines: lines)
        }.value
    }
}

private struct ReceiptCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
