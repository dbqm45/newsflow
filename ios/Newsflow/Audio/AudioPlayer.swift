import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Jedna pozycja do odtworzenia (np. pełna audycja dnia z rozdziałami).
struct Track: Identifiable, Equatable {
    let id: UUID              // audio_assets.id
    let title: String
    let subtitle: String
    let storagePath: String
    let duration: Double
    let chapters: [Chapter]
    /// Tekst każdego rozdziału (ze scenariusza) — do widoku „Tekst”.
    let texts: [String]
    /// Okładka każdego rozdziału (wg podkategorii tematu).
    let styles: [CoverStyle]
    let briefingDate: String?

    static func from(_ b: Briefing) -> Track? {
        guard let assetId = b.audioAssetId, let path = b.audioPath else { return nil }
        return Track(id: assetId, title: b.title, subtitle: "AI Daily · \(Fmt.dayLong(b.briefingDate))",
                     storagePath: path, duration: b.audioDurationSeconds ?? b.chapters.reduce(0) { $0 + $1.durationSeconds },
                     chapters: b.chapters,
                     texts: b.chapters.map { b.scriptText(for: $0) ?? "" },
                     styles: b.chapters.map { b.style(for: $0) },
                     briefingDate: b.briefingDate)
    }
}

/// Odtwarzacz w stylu aplikacji muzycznych: odtwarzanie w tle, ekran blokady,
/// prędkość, rozdziały, kolejka i zapamiętywanie pozycji (playback_progress).
@MainActor
@Observable
final class AudioPlayer {
    static let shared = AudioPlayer()
    static let rates: [Float] = [0.8, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0]

    private(set) var current: Track?
    private(set) var queue: [Track] = []
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var duration: Double = 0
    var currentTime: Double = 0
    var isScrubbing = false
    var errorMessage: String?
    var rate: Float = UserDefaults.standard.object(forKey: "playbackRate") as? Float ?? 1.0 {
        didSet {
            UserDefaults.standard.set(rate, forKey: "playbackRate")
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
            updateNowPlaying()
        }
    }

    var currentChapter: Chapter? {
        current?.chapters.last { $0.startSeconds <= currentTime + 0.5 }
    }

    /// Okładka bieżącego rozdziału (kolor tła odtwarzacza).
    var currentStyle: CoverStyle {
        guard let t = current, let ch = currentChapter, ch.index < t.styles.count else { return .daily }
        return t.styles[ch.index]
    }

    /// Tekst bieżącego rozdziału podzielony na akapity.
    var currentParagraphs: [String] {
        guard let t = current, let ch = currentChapter, ch.index < t.texts.count else { return [] }
        return t.texts[ch.index].components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Postęp w bieżącym rozdziale 0…1.
    var chapterProgress: Double {
        guard let ch = currentChapter, ch.durationSeconds > 0 else { return 0 }
        return min(max((currentTime - ch.startSeconds) / ch.durationSeconds, 0), 1)
    }

    /// Indeks czytanego akapitu — szacowany proporcjonalnie do długości akapitów.
    var currentParagraphIndex: Int {
        let paras = currentParagraphs
        guard !paras.isEmpty else { return 0 }
        let total = Double(paras.reduce(0) { $0 + $1.count })
        var acc = 0.0
        for (i, p) in paras.enumerated() {
            acc += Double(p.count) / total
            if chapterProgress < acc { return i }
        }
        return paras.count - 1
    }

    var chapterLabel: String {
        guard let t = current, let ch = currentChapter else { return "" }
        return "Rozdział \(ch.index + 1) z \(t.chapters.count)"
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastSave = Date.distantPast
    private static let artwork: MPMediaItemArtwork = {
        let image = makeArtwork()
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    private init() {
        player.defaultRate = rate
        player.automaticallyWaitsToMinimizeStalling = true
        configureSession()
        configureRemoteCommands()
        observeTime()
        observeNotifications()
    }

    // MARK: Sterowanie

    func play(_ track: Track, from start: Double? = nil) async {
        if current?.id == track.id {
            if let start { seek(to: start) }
            resume()
            return
        }
        persistProgress(force: true)
        current = track
        duration = track.duration
        currentTime = start ?? 0
        isLoading = true
        errorMessage = nil
        do {
            let url = try await API.signedURL(path: track.storagePath)
            let item = AVPlayerItem(url: url)
            item.audioTimePitchAlgorithm = .timeDomain   // naturalna mowa przy szybszym tempie
            player.replaceCurrentItem(with: item)
            if let start, start > 1 {
                _ = await player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
            }
            try? AVAudioSession.sharedInstance().setActive(true)
            player.playImmediately(atRate: rate)
            isPlaying = true
        } catch {
            errorMessage = "Nie udało się wczytać nagrania: \(error.localizedDescription)"
            isPlaying = false
        }
        isLoading = false
        updateNowPlaying()
    }

    func togglePlay() { isPlaying ? pause() : resume() }

    func resume() {
        guard player.currentItem != nil else { return }
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        persistProgress(force: true)
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        let t = max(0, min(seconds, max(duration - 0.5, 0)))
        currentTime = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func skip(_ delta: Double) { seek(to: currentTime + delta) }

    func nextChapter() {
        guard let chapters = current?.chapters,
              let next = chapters.first(where: { $0.startSeconds > currentTime + 0.5 }) else {
            playNextInQueue()
            return
        }
        seek(to: next.startSeconds)
    }

    func previousChapter() {
        guard let ch = currentChapter else { seek(to: 0); return }
        if currentTime - ch.startSeconds > 3 || ch.index == 0 {
            seek(to: ch.startSeconds)
        } else if let prev = current?.chapters.last(where: { $0.startSeconds < ch.startSeconds }) {
            seek(to: prev.startSeconds)
        }
    }

    func enqueue(_ track: Track) {
        guard track.id != current?.id, !queue.contains(track) else { return }
        queue.append(track)
    }

    func removeFromQueue(_ track: Track) { queue.removeAll { $0 == track } }

    func stop() {
        persistProgress(force: true)
        player.replaceCurrentItem(with: nil)
        current = nil
        isPlaying = false
        currentTime = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func playNextInQueue() {
        guard !queue.isEmpty else { pause(); return }
        let next = queue.removeFirst()
        Task { await play(next) }
    }

    // MARK: Postęp

    private func persistProgress(force: Bool = false, completed: Bool = false) {
        guard let track = current, currentTime > 1 || completed else { return }
        guard force || Date().timeIntervalSince(lastSave) > 15 else { return }
        lastSave = Date()
        let position = currentTime
        Task.detached { await API.saveProgress(assetId: track.id, position: position, completed: completed) }
    }

    // MARK: Konfiguracja

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
    }

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0, abs(d - self.duration) > 1 {
                    self.duration = d
                    self.updateNowPlaying()
                }
                if self.isPlaying { self.persistProgress() }
            }
        }
    }

    private func observeNotifications() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.persistProgress(force: true, completed: true)
                self.isPlaying = false
                self.playNextInQueue()
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
                switch type {
                case .began:
                    self.isPlaying = false
                    self.persistProgress(force: true)
                case .ended:
                    if let optionsRaw, AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) { self.resume() }
                @unknown default: break
                }
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                // Słuchawki odłączone -> pauza (jak w Spotify)
                if let reasonRaw, AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable { self?.pause() }
            }
        })
    }

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.togglePlay() }; return .success }
        c.skipForwardCommand.preferredIntervals = [30]
        c.skipForwardCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.skip(30) }; return .success }
        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.skip(-15) }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.nextChapter() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.previousChapter() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
        c.changePlaybackRateCommand.supportedPlaybackRates = Self.rates.map { NSNumber(value: $0) }
        c.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.rate = e.playbackRate }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentChapter.map { "\($0.title) — \(track.title)" } ?? track.title,
            MPMediaItemPropertyArtist: "NEWSFLOW · głos AI",
            MPMediaItemPropertyAlbumTitle: track.subtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPMediaItemPropertyArtwork: Self.artwork,
        ]
        if let ch = currentChapter, let count = current?.chapters.count {
            info[MPNowPlayingInfoPropertyChapterNumber] = ch.index
            info[MPNowPlayingInfoPropertyChapterCount] = count
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private static func makeArtwork() -> UIImage {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1).cgColor,
                          UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let config = UIImage.SymbolConfiguration(pointSize: 260, weight: .semibold)
            if let symbol = UIImage(systemName: "waveform", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2))
            }
        }
    }
}
