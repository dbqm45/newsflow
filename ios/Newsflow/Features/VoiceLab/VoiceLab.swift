import AVFoundation
import Foundation
import Observation
import Supabase

/// Logika ekranu „Porównanie głosów”: głos systemowy iOS (lokalnie, za darmo)
/// oraz OpenAI TTS i ElevenLabs (przez funkcję Supabase `tts-preview`).
@MainActor
@Observable
final class VoiceLab: NSObject {
    enum Provider: String, CaseIterable, Identifiable {
        case system, openai, elevenlabs
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "Głos systemowy iOS"
            case .openai: return "OpenAI TTS"
            case .elevenlabs: return "ElevenLabs"
            }
        }
        var costHint: String {
            switch self {
            case .system: return "0 zł · offline · bez czekania"
            case .openai: return "~0,015 USD/min (gpt-4o-mini-tts)"
            case .elevenlabs: return "~0,22 USD/1000 znaków (flash: połowa)"
            }
        }
    }

    struct Sample: Equatable {
        var url: URL?
        var generationMs: Int = 0
        var costUsd: Double = 0
        var cached = false
        var characters = 0
        var paramsKey = ""
    }

    static let maxChars = 1500
    static let defaultText = """
    Dzień dobry, oto NEWSFLOW, wydanie z dwudziestego listopada. Audycję przygotowała i czyta sztuczna inteligencja.

    Najważniejsza informacja dnia: OpenAI udostępniło nową wersję modelu GPT, która według firmy o czterdzieści procent szybciej rozwiązuje zadania programistyczne. To deklaracja producenta — niezależnych testów jeszcze nie ma.

    Zostańmy przy narzędziach. Hugging Face opublikowało otwarty zbiór danych do trenowania agentów, a Anthropic i Google DeepMind zapowiedziały wspólne badania nad bezpieczeństwem. Dla praktyków oznacza to jedno: automatyzacje oparte na agentach AI będą tańsze i łatwiejsze do wdrożenia.
    """

    var text = VoiceLab.defaultText
    var playing: Provider?
    var busy: Provider?
    var errors: [Provider: String] = [:]
    var results: [Provider: Sample] = [:]
    var ratings: [Provider: Int] = VoiceLab.loadRatings()

    // System
    var systemVoices: [AVSpeechSynthesisVoice] = []
    var systemVoiceId: String = ""
    var systemRate: Float = AVSpeechUtteranceDefaultSpeechRate

    // OpenAI
    static let openAIVoices = ["coral", "nova", "sage", "shimmer", "alloy", "ash", "ballad", "echo", "fable", "onyx", "verse"]
    static let openAIModels = ["gpt-4o-mini-tts", "tts-1-hd", "tts-1"]
    var openAIVoice = "coral"
    var openAIModel = "gpt-4o-mini-tts"
    var openAIInstructions = "Mów po polsku spokojnym, rzeczowym tonem profesjonalnego lektora serwisu informacyjnego. Naturalne pauzy między akapitami. Nazwy angielskie wymawiaj po angielsku."

    // ElevenLabs
    static let elevenModels = ["eleven_multilingual_v2", "eleven_flash_v2_5", "eleven_v3"]
    var elevenModel = "eleven_multilingual_v2"
    var elevenVoiceId = ""   // puste = app_config.elevenlabs.voice_id

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        systemVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("pl") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        systemVoiceId = systemVoices.first?.identifier ?? ""
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.playing != .system { self?.playing = nil } }
        }
    }

    var trimmedText: String { String(text.prefix(Self.maxChars)) }

    // MARK: Odtwarzanie

    func toggle(_ provider: Provider) async {
        if playing == provider { stop(); return }
        stop()
        AudioPlayer.shared.pause()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        errors[provider] = nil

        if provider == .system {
            let u = AVSpeechUtterance(string: trimmedText)
            u.voice = AVSpeechSynthesisVoice(identifier: systemVoiceId) ?? AVSpeechSynthesisVoice(language: "pl-PL")
            u.rate = systemRate
            u.postUtteranceDelay = 0.2
            synthesizer.speak(u)
            playing = .system
            return
        }

        let params = paramsKey(provider)
        if let r = results[provider], let url = r.url, r.paramsKey == params {
            play(url, provider)
            return
        }
        busy = provider
        defer { busy = nil }
        do {
            let resp: PreviewResponse = try await Supa.client.functions.invoke(
                "tts-preview",
                options: FunctionInvokeOptions(body: request(for: provider)),
                decoder: JSONCoding.decoder
            )
            guard let url = URL(string: resp.url) else { throw URLError(.badURL) }
            let r = Sample(url: url, generationMs: resp.generationMs, costUsd: resp.costUsd, cached: resp.cached,
                           characters: resp.characters, paramsKey: params)
            results[provider] = r
            play(url, provider)
        } catch {
            errors[provider] = Self.describe(error)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player.pause()
        playing = nil
    }

    private func play(_ url: URL, _ provider: Provider) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        playing = provider
    }

    // MARK: Oceny (lokalnie)

    func rate(_ provider: Provider, _ stars: Int) {
        ratings[provider] = stars
        UserDefaults.standard.set(ratings.reduce(into: [String: Int]()) { $0[$1.key.rawValue] = $1.value }, forKey: "voiceLabRatings")
    }

    private static func loadRatings() -> [Provider: Int] {
        let raw = UserDefaults.standard.dictionary(forKey: "voiceLabRatings") as? [String: Int] ?? [:]
        return raw.reduce(into: [:]) { acc, kv in if let p = Provider(rawValue: kv.key) { acc[p] = kv.value } }
    }

    // MARK: Pomocnicze

    /// Wczytuje fragment scenariusza ostatniego briefingu (rozdział z najważniejszym tematem).
    func loadFromLatestBriefing() async {
        struct Row: Decodable { struct Script: Decodable { struct Ch: Decodable { let kind: String; let text: String }; let chapters: [Ch] }; let script: Script? }
        do {
            let resp = try await Supa.client.from("daily_briefings").select("script")
                .order("briefing_date", ascending: false).limit(5).execute()
            let rows = try JSONCoding.decoder.decode([Row].self, from: resp.data)
            let script = rows.compactMap(\.script).first
            if let ch = script?.chapters.first(where: { $0.kind == "headline" }) ?? script?.chapters.first {
                text = String(ch.text.prefix(Self.maxChars))
            } else {
                errors[.system] = "Brak briefingu ze scenariuszem audio — zostaje tekst przykładowy."
            }
        } catch {
            errors[.system] = "Nie udało się wczytać briefingu: \(error.localizedDescription)"
        }
    }

    private func request(for provider: Provider) -> PreviewRequest {
        switch provider {
        case .openai:
            return PreviewRequest(provider: "openai", text: trimmedText, model: openAIModel, voice: openAIVoice,
                                  instructions: openAIModel == "gpt-4o-mini-tts" ? openAIInstructions : nil)
        default:
            return PreviewRequest(provider: "elevenlabs", text: trimmedText, model: elevenModel,
                                  voice: elevenVoiceId.trimmingCharacters(in: .whitespaces).isEmpty ? nil : elevenVoiceId, instructions: nil)
        }
    }

    private func paramsKey(_ provider: Provider) -> String {
        switch provider {
        case .system: return ""
        case .openai: return [trimmedText, openAIModel, openAIVoice, openAIInstructions].joined(separator: "|")
        case .elevenlabs: return [trimmedText, elevenModel, elevenVoiceId].joined(separator: "|")
        }
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? FunctionsError, case let .httpError(code, data) = e {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            return "Błąd \(code): \(msg ?? "funkcja tts-preview")"
        }
        return error.localizedDescription
    }
}

extension VoiceLab: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.playing == .system { self.playing = nil } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.playing == .system { self.playing = nil } }
    }
}

private struct PreviewRequest: Encodable {
    let provider: String
    let text: String
    let model: String
    let voice: String?
    let instructions: String?
}

private struct PreviewResponse: Decodable {
    let url: String
    let cached: Bool
    let costUsd: Double
    let generationMs: Int
    let characters: Int
}
