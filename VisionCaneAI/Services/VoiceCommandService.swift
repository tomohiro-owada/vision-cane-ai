import AVFoundation
import Foundation
import Speech

/// 音声コマンド入力を扱うサービス。
///
/// - 「前方は？」「コンビニはどこ？」などの問いかけを `SFSpeechRecognizer` で
///   テキスト化し、`commandPublisher` に流す。
/// - 完全ローカル動作のため、`requiresOnDeviceRecognition = true` を強制する。
///   iOS 13+ の日本語オンデバイスモデルが利用できない端末では初期化に失敗する。
final class VoiceCommandService {

    enum Command: Equatable {
        case describeFront    // 前方は？
        case findPlace(String) // コンビニは？ 駅は？
        case raw(String)       // 解釈不能な音声
    }

    typealias Handler = (Command) -> Void

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var handler: Handler?

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// 権限を要求し、成功時に継続的なコマンド受付を開始する。
    func requestAuthorizationAndStart(handler: @escaping Handler) {
        self.handler = handler
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                NSLog("[VoiceCommandService] authorization denied: \(status.rawValue)")
                return
            }
            DispatchQueue.main.async { self?.startRecognition() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func startRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            NSLog("[VoiceCommandService] recognizer unavailable")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do { try audioEngine.start() } catch {
            NSLog("[VoiceCommandService] audioEngine start failed: \(error)")
            return
        }

        self.request = request
        self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                NSLog("[VoiceCommandService] recognition error: \(error)")
                return
            }
            guard let result, result.isFinal else { return }
            let text = result.bestTranscription.formattedString
            let command = Self.parse(text)
            self.handler?(command)
        }
    }

    static func parse(_ text: String) -> Command {
        let normalized = text.replacingOccurrences(of: "？", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("前方") || normalized.contains("何が") || normalized.contains("前は") {
            return .describeFront
        }
        if let match = normalized.range(of: "[ぁ-んァ-ン一-龥ー]+は(どこ|ある)", options: .regularExpression) {
            let noun = String(normalized[match.lowerBound...])
                .replacingOccurrences(of: "はどこ", with: "")
                .replacingOccurrences(of: "はある", with: "")
            return .findPlace(noun)
        }
        return .raw(normalized)
    }
}
