import AVFoundation
import SwiftUI

/// Ekran porównania głosów: ten sam tekst czytany przez głos systemowy iOS, OpenAI TTS i ElevenLabs.
struct VoiceLabView: View {
    @State private var lab = VoiceLab()

    var body: some View {
        Form {
            Section {
                TextEditor(text: $lab.text)
                    .frame(minHeight: 160)
                    .font(.callout)
                HStack {
                    Text("\(min(lab.text.count, VoiceLab.maxChars))/\(VoiceLab.maxChars) znaków")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(lab.text.count > VoiceLab.maxChars ? .red : .secondary)
                    Spacer()
                    Menu("Tekst") {
                        Button("Fragment ostatniego briefingu") { Task { await lab.loadFromLatestBriefing() } }
                        Button("Tekst przykładowy") { lab.text = VoiceLab.defaultText }
                    }
                    .font(.caption)
                }
            } header: { Text("Tekst do odczytania") } footer: {
                Text("Wszystkie głosy czytają ten sam tekst. Próbki OpenAI i ElevenLabs są zapisywane — ponowne odtworzenie nic nie kosztuje.")
            }

            systemSection
            openAISection
            elevenSection
            summarySection
        }
        .navigationTitle("Porównanie głosów")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { lab.stop() }
    }

    // MARK: Sekcje

    private var systemSection: some View {
        Section {
            if lab.systemVoices.isEmpty {
                Text("Brak polskich głosów systemowych.").foregroundStyle(.secondary)
            } else {
                Picker("Głos", selection: $lab.systemVoiceId) {
                    ForEach(lab.systemVoices, id: \.identifier) { v in
                        Text("\(v.name) · \(qualityLabel(v.quality))").tag(v.identifier)
                    }
                }
            }
            VStack(alignment: .leading) {
                Text("Tempo").font(.caption).foregroundStyle(.secondary)
                Slider(value: $lab.systemRate, in: AVSpeechUtteranceMinimumSpeechRate...0.65)
            }
            playRow(.system)
        } header: { header(.system) } footer: {
            Text("Lepsze głosy pobierzesz za darmo: Ustawienia iOS → Dostępność → Treść mówiona → Głosy → Polski → wersja „Rozszerzona” lub „Premium”. Potem wróć na ten ekran.")
        }
    }

    private var openAISection: some View {
        Section {
            Picker("Model", selection: $lab.openAIModel) {
                ForEach(VoiceLab.openAIModels, id: \.self) { Text($0).tag($0) }
            }
            Picker("Głos", selection: $lab.openAIVoice) {
                ForEach(VoiceLab.openAIVoices, id: \.self) { Text($0.capitalized).tag($0) }
            }
            if lab.openAIModel == "gpt-4o-mini-tts" {
                TextField("Instrukcja stylu", text: $lab.openAIInstructions, axis: .vertical)
                    .font(.caption)
                    .lineLimit(2...5)
            }
            playRow(.openai)
        } header: { header(.openai) }
    }

    private var elevenSection: some View {
        Section {
            Picker("Model", selection: $lab.elevenModel) {
                ForEach(VoiceLab.elevenModels, id: \.self) { Text($0).tag($0) }
            }
            TextField("Voice ID (puste = z app_config)", text: $lab.elevenVoiceId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
            playRow(.elevenlabs)
        } header: { header(.elevenlabs) } footer: {
            Text("Voice ID skopiujesz z ElevenLabs → Voice Library → Twój głos. Możesz porównać kilka głosów, zmieniając ID.")
        }
    }

    private var summarySection: some View {
        Section("Twoje oceny") {
            ForEach(VoiceLab.Provider.allCases) { p in
                HStack {
                    Text(p.title)
                    Spacer()
                    Text(String(repeating: "★", count: lab.ratings[p] ?? 0) + String(repeating: "☆", count: 5 - (lab.ratings[p] ?? 0)))
                        .foregroundStyle(.orange)
                }
            }
            Text("Oceny są zapisywane tylko na tym telefonie. Podpowiedź: oceniaj wymowę nazw angielskich, naturalność intonacji i to, czy dałbyś radę słuchać 10 minut.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Elementy

    private func header(_ p: VoiceLab.Provider) -> some View {
        HStack {
            Text(p.title)
            Spacer()
            Text(p.costHint).textCase(nil).font(.caption2)
        }
    }

    @ViewBuilder
    private func playRow(_ p: VoiceLab.Provider) -> some View {
        HStack(spacing: 12) {
            Button { Task { await lab.toggle(p) } } label: {
                if lab.busy == p {
                    HStack { ProgressView(); Text("Generuję…") }
                } else {
                    Label(lab.playing == p ? "Zatrzymaj" : "Odtwórz",
                          systemImage: lab.playing == p ? "stop.fill" : "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(lab.busy != nil || lab.trimmedText.isEmpty)
            Spacer()
            StarRating(value: lab.ratings[p] ?? 0) { lab.rate(p, $0) }
        }
        if let r = lab.results[p] {
            Text(r.cached ? "Z pamięci podręcznej · 0 USD"
                 : String(format: "Wygenerowano w %.1f s · koszt ~%.3f USD · %d znaków", Double(r.generationMs) / 1000, r.costUsd, r.characters))
                .font(.caption).foregroundStyle(.secondary)
        }
        if let e = lab.errors[p] {
            Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
    }

    private func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium: return "Premium"
        case .enhanced: return "Rozszerzony"
        default: return "Podstawowy"
        }
    }
}

struct StarRating: View {
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star")
                    .foregroundStyle(.orange)
                    .onTapGesture { onChange(i == value ? 0 : i) }
                    .accessibilityLabel("\(i) gwiazdek")
            }
        }
        .font(.footnote)
    }
}
