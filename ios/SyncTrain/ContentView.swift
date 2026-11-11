import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @AppStorage("synctrain_server_url") private var serverURL: String = "http://192.168.1.25:8094"

    @State private var showingImporter = false
    @State private var webReloadToken = UUID()
    @State private var isUsingOfflineFallback = false

    private let bgColor = Color(red: 9 / 255, green: 14 / 255, blue: 24 / 255)
    private let cardColor = Color(red: 17 / 255, green: 24 / 255, blue: 40 / 255)
    private let accentColor = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)

    var body: some View {
        TabView {
            playerTab
                .tabItem {
                    Label("Lecteur", systemImage: "headphones")
                }

            syncTab
                .tabItem {
                    Label("Synchro LAN", systemImage: "arrow.triangle.2.circlepath")
                }

            webTab
                .tabItem {
                    Label("Compagnon Web", systemImage: "globe")
                }
        }
        .tint(accentColor)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                player.importFiles(urls: urls)
            }
        }
    }

    private var playerTab: some View {
        NavigationStack {
            ZStack {
                bgColor.ignoresSafeArea()

                VStack(spacing: 16) {
                    nowPlayingCard

                    HStack {
                        Text("Bibliothèque Hors-Ligne (\(player.tracks.count))")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            player.scanLocalLibrary()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Importer", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)

                    if player.tracks.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 38))
                                .foregroundColor(.secondary)
                            Text("Aucune piste hors-ligne")
                                .font(.headline)
                            Text("Appuyez sur Importer ou déposez vos MP3 / M4A / WAV dans Fichiers -> Sur mon iPhone -> SyncTrain.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(player.tracks) { track in
                                Button {
                                    player.play(track: track)
                                } label: {
                                    HStack {
                                        Image(systemName: player.currentTrack?.id == track.id && player.isPlaying ? "speaker.wave.2.fill" : "music.note")
                                            .foregroundColor(player.currentTrack?.id == track.id ? accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Text("\(track.fileExtension) • \(formatSize(track.sizeBytes))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .listRowBackground(cardColor)
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    player.deleteTrack(player.tracks[index])
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("SyncTrain Audio")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var nowPlayingCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Mode Hors-Ligne 100%", systemImage: "airplane")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.green)
                Spacer()
                Button {
                    player.isShuffleEnabled.toggle()
                } label: {
                    Label(
                        player.isShuffleEnabled ? "Aléatoire ON" : "Séquentiel",
                        systemImage: "shuffle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(player.isShuffleEnabled ? accentColor : .secondary)
                }
            }

            Text(player.currentTrack?.title ?? "Aucune piste sélectionnée")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(player.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .tint(accentColor)

            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundColor(.secondary)

            HStack(spacing: 24) {
                Button {
                    player.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(accentColor)
                }

                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }

                Button {
                    player.playRandom()
                } label: {
                    Image(systemName: "shuffle.circle")
                        .font(.title2)
                }
            }
            .foregroundColor(.white)
        }
        .padding()
        .background(cardColor)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var syncTab: some View {
        NavigationStack {
            ZStack {
                bgColor.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Serveur Desktop SyncTrain")
                                .font(.headline)
                            Text("Adresse HTTP de server.py sur votre réseau local (port 8094).")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("http://192.168.1.25:8094", text: $serverURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.URL)
                                .padding(10)
                                .background(bgColor)
                                .cornerRadius(10)

                            Button {
                                player.fetchRemoteSync(baseURLString: serverURL)
                            } label: {
                                HStack {
                                    if player.isSyncingRemote {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text("Tester & Synchroniser")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accentColor)
                            .foregroundColor(.black)
                        }
                        .padding()
                        .background(cardColor)
                        .cornerRadius(16)

                        if let err = player.remoteSyncError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(cardColor)
                                .cornerRadius(12)
                        }

                        if let sync = player.remoteSyncStatus {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Statut Réseau Desktop")
                                    .font(.headline)
                                Text("Mode : \(sync.mode)")
                                    .font(.caption)
                                Text("Pairs à proximité : \(sync.peers_nearby)")
                                    .font(.caption)
                                Text("Dossier source : \(sync.synced_folder)")
                                    .font(.caption)
                                Text("Dernière synchro : \(sync.last_sync)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardColor)
                            .cornerRadius(16)
                        }

                        if !player.remoteTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Catalogue Desktop (\(player.remoteTracks.count))")
                                    .font(.headline)
                                ForEach(player.remoteTracks) { track in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text(track.artist)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(track.duration)
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(accentColor)
                                    }
                                    Divider().background(Color.white.opacity(0.08))
                                }
                            }
                            .padding()
                            .background(cardColor)
                            .cornerRadius(16)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Synchronisation Proximité")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var webTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isUsingOfflineFallback {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("Compagnon hors-ligne embarqué (serveur desktop non joignable)")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.18))
                    .foregroundColor(.orange)
                }

                WebCompanionView(
                    urlString: serverURL,
                    reloadToken: webReloadToken,
                    isUsingOfflineFallback: $isUsingOfflineFallback
                )
            }
            .navigationTitle("Compagnon Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        webReloadToken = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
