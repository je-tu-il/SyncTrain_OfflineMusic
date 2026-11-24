import AVFoundation
import Combine
import Foundation
import MediaPlayer

struct LocalTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let fileExtension: String
    let url: URL
    let sizeBytes: Int64
}

struct RemoteSyncTrack: Codable, Identifiable {
    let id: Int
    let title: String
    let artist: String
    let duration: String
    let synced: Bool
}

struct RemoteSyncStatus: Codable {
    let mode: String
    let internet_required: Bool
    let peers_nearby: Int
    let last_sync: String
    let synced_folder: String
}

struct RemoteSyncResponse: Codable {
    let sync: RemoteSyncStatus
    let tracks: [RemoteSyncTrack]
}

final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var tracks: [LocalTrack] = []
    @Published var currentTrack: LocalTrack?
    @Published var isPlaying: Bool = false
    @Published var isShuffleEnabled: Bool = true
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var statusMessage: String = "Prêt pour l'écoute hors-ligne"

    @Published var remoteSyncStatus: RemoteSyncStatus?
    @Published var remoteTracks: [RemoteSyncTrack] = []
    @Published var isSyncingRemote: Bool = false
    @Published var remoteSyncError: String?

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "caf"]

    var musicDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SyncTrainMusic", isDirectory: true)
    }

    override init() {
        super.init()
        ensureMusicDirectory()
        configureAudioSession()
        configureRemoteCommands()
        scanLocalLibrary()
    }

    deinit {
        progressTimer?.invalidate()
    }

    private func ensureMusicDirectory() {
        try? FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
        } catch {
            statusMessage = "Session audio limitée : \(error.localizedDescription)"
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.resumeOrPlayFirst()
            }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.pause()
            }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.playNext()
            }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.playPrevious()
            }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            DispatchQueue.main.async {
                self.seek(to: posEvent.positionTime)
            }
            return .success
        }
    }

    func scanLocalLibrary() {
        ensureMusicDirectory()
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

        var foundURLs: [URL] = []
        for folder in [musicDirectory, docs] {
            if let items = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in items {
                    let ext = url.pathExtension.lowercased()
                    if supportedExtensions.contains(ext),
                       (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                        foundURLs.append(url)
                    }
                }
            }
        }

        let uniqueByPath = Dictionary(grouping: foundURLs, by: { $0.path }).compactMap { $0.value.first }
        let sorted = uniqueByPath.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        tracks = sorted.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(values?.fileSize ?? 0)
            return LocalTrack(
                id: url.path,
                title: url.deletingPathExtension().lastPathComponent,
                fileExtension: url.pathExtension.uppercased(),
                url: url,
                sizeBytes: size
            )
        }

        if let current = currentTrack, !tracks.contains(where: { $0.id == current.id }) {
            stop()
        }
    }

    func importFiles(urls: [URL]) {
        ensureMusicDirectory()
        var importedCount = 0

        for url in urls {
            let needsStop = url.startAccessingSecurityScopedResource()
            defer {
                if needsStop {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let target = uniqueDestinationURL(for: url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: target)
                importedCount += 1
            } catch {
                statusMessage = "Erreur import \(url.lastPathComponent) : \(error.localizedDescription)"
            }
        }

        scanLocalLibrary()
        if importedCount > 0 {
            statusMessage = "\(importedCount) morceau(x) importé(s) hors-ligne."
        }
    }

    private func uniqueDestinationURL(for filename: String) -> URL {
        let fm = FileManager.default
        var candidate = musicDirectory.appendingPathComponent(filename)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 1
        while fm.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(stem)_\(index)" : "\(stem)_\(index).\(ext)"
            candidate = musicDirectory.appendingPathComponent(nextName)
            index += 1
        }
        return candidate
    }

    func deleteTrack(_ track: LocalTrack) {
        if currentTrack?.id == track.id {
            stop()
        }
        try? FileManager.default.removeItem(at: track.url)
        scanLocalLibrary()
    }

    func play(track: LocalTrack) {
        do {
            let player = try AVAudioPlayer(contentsOf: track.url)
            player.delegate = self
            guard player.prepareToPlay() else { throw CocoaError(.fileReadCorruptFile) }
            try AVAudioSession.sharedInstance().setActive(true)
            guard player.play() else { throw CocoaError(.fileReadUnknown) }

            audioPlayer?.stop()
            audioPlayer = player
            currentTrack = track
            duration = player.duration
            currentTime = 0
            isPlaying = true
            statusMessage = "Lecture hors-ligne : \(track.title)"
            startProgressTimer()
            updateNowPlayingInfo()
        } catch {
            isPlaying = audioPlayer?.isPlaying ?? false
            statusMessage = "Impossible de lire \(track.title) : \(error.localizedDescription)"
        }
    }

    func resumeOrPlayFirst() {
        if let player = audioPlayer {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                statusMessage = "La session audio est indisponible."
                return
            }
            guard player.play() else {
                statusMessage = "Impossible de reprendre la lecture."
                return
            }
            isPlaying = true
            startProgressTimer()
            updateNowPlayingInfo()
        } else if let first = isShuffleEnabled ? tracks.randomElement() : tracks.first {
            play(track: first)
        } else {
            statusMessage = "Importez d'abord des fichiers audio dans l'onglet Lecteur."
        }
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        updateNowPlayingInfo()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentTrack = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        progressTimer?.invalidate()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resumeOrPlayFirst()
        }
    }

    func playRandom() {
        guard !tracks.isEmpty else {
            statusMessage = "Aucune piste hors-ligne disponible."
            return
        }
        if tracks.count == 1, let only = tracks.first {
            play(track: only)
            return
        }
        let candidates = tracks.filter { $0.id != currentTrack?.id }
        if let picked = candidates.randomElement() {
            play(track: picked)
        }
    }

    func playNext() {
        guard !tracks.isEmpty else { return }
        if isShuffleEnabled {
            playRandom()
            return
        }
        if let current = currentTrack, let idx = tracks.firstIndex(of: current) {
            let nextIdx = (idx + 1) % tracks.count
            play(track: tracks[nextIdx])
        } else if let first = tracks.first {
            play(track: first)
        }
    }

    func playPrevious() {
        guard !tracks.isEmpty else { return }
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        if let current = currentTrack, let idx = tracks.firstIndex(of: current) {
            let prevIdx = (idx - 1 + tracks.count) % tracks.count
            play(track: tracks[prevIdx])
        } else if let first = tracks.first {
            play(track: first)
        }
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
        currentTime = clamped
        updateNowPlayingInfo()
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
            self.duration = player.duration
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: "SyncTrain OfflineMusic",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if #available(iOS 10.0, *) {
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            playNext()
        } else {
            isPlaying = false
            progressTimer?.invalidate()
        }
    }

    func fetchRemoteSync(baseURLString: String) {
        guard !isSyncingRemote else { return }
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let baseURL = URL(string: trimmed),
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              baseURL.host != nil, baseURL.user == nil, baseURL.password == nil else {
            remoteSyncError = "Adresse serveur invalide (ex : http://192.168.1.25:8094)."
            return
        }

        let endpoint = baseURL.appendingPathComponent("api/sync_music")
        isSyncingRemote = true
        remoteSyncError = nil

        Task { @MainActor in
            do {
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 5.0
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let decoded = try JSONDecoder().decode(RemoteSyncResponse.self, from: data)
                self.remoteSyncStatus = decoded.sync
                self.remoteTracks = decoded.tracks
                self.isSyncingRemote = false
            } catch {
                self.isSyncingRemote = false
                self.remoteSyncError = "Serveur desktop inaccessible (\(error.localizedDescription)). Mode 100% hors-ligne actif."
            }
        }
    }
}
