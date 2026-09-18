import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

struct AudiobookPlayerView: View {
    let audiobook: Audiobook
    @ObservedObject private var player: AudiobookPlayerModel
    @State private var showingBookmarkEditor = false
    private let clock = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(audiobook: Audiobook) {
        self.audiobook = audiobook
        _player = ObservedObject(wrappedValue: AudiobookPlaybackStore.shared.player(for: audiobook))
    }

    init(player: AudiobookPlayerModel) {
        self.audiobook = player.audiobook
        _player = ObservedObject(wrappedValue: player)
    }

    var body: some View {
        VStack(spacing: 28) {
            Group {
                if let data = audiobook.coverData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "headphones.circle.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(.indigo)
                }
            }
            .frame(maxWidth: 320, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 10)
            Text(audiobook.title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(audiobook.author).foregroundStyle(.secondary)
            Picker("Chapter", selection: $player.chapterIndex) {
                ForEach(Array(audiobook.chapters.enumerated()), id: \.offset) { index, chapter in
                    Text(chapter.title).tag(index)
                }
            }
            .pickerStyle(.menu)
            Slider(value: Binding(get: { player.progress }, set: { player.previewProgress($0) }), in: 0...1) { editing in
                if !editing { player.seek(toProgress: player.progress) }
            }
            HStack {
                Text(player.elapsedText)
                Spacer()
                Text("Chapter \(Int((player.progress * 100).rounded()))%")
                Spacer()
                Text("–\(player.remainingText)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            HStack {
                Picker("Speed", selection: $player.speed) {
                    Text("0.75×").tag(Float(0.75))
                    Text("1×").tag(Float(1.0))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                    Text("2×").tag(Float(2.0))
                }
                .pickerStyle(.menu)

                Spacer()

                Menu {
                    Button("Off") { player.setSleepTimer(nil) }
                    Divider()
                    Button("15 minutes") { player.setSleepTimer(15 * 60) }
                    Button("30 minutes") { player.setSleepTimer(30 * 60) }
                    Button("45 minutes") { player.setSleepTimer(45 * 60) }
                    Button("60 minutes") { player.setSleepTimer(60 * 60) }
                } label: {
                    Label(player.sleepTimerLabel, systemImage: "moon.zzz")
                }
            }
            .font(.subheadline)
            HStack(spacing: 40) {
                Button { player.previousChapter() } label: { Image(systemName: "backward.end.fill") }.font(.title3)
                Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }.font(.title2)
                Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill") }.font(.system(size: 64))
                Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30") }.font(.title2)
                Button { player.nextChapter() } label: { Image(systemName: "forward.end.fill") }.font(.title3)
            }
            HStack {
                Button { showingBookmarkEditor = true } label: { Label("Bookmark", systemImage: "bookmark") }
                Spacer()
                if !player.bookmarks.isEmpty {
                    Menu {
                        ForEach(player.bookmarks) { bookmark in
                            Button("Chapter \(bookmark.chapterIndex + 1) · \(player.formatTime(bookmark.time))") {
                                player.jump(to: bookmark)
                            }
                        }
                    } label: { Label("Bookmarks", systemImage: "bookmarks") }
                }
            }
            .font(.subheadline)
        }
        .padding(32)
        .onAppear {
            AudiobookPlaybackStore.shared.activate(player)
            AudiobookPlaybackStore.shared.setFullPlayerVisible(true)
        }
        .onDisappear {
            AudiobookPlaybackStore.shared.setFullPlayerVisible(false)
        }
        .navigationTitle("Audiobook")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(clock) { _ in player.refresh() }
        .sheet(isPresented: $showingBookmarkEditor) {
            BookmarkEditor { note in player.addBookmark(note: note); showingBookmarkEditor = false }
        }
    }
}

@MainActor final class AudiobookPlaybackStore: ObservableObject {
    static let shared = AudiobookPlaybackStore()
    @Published private(set) var currentPlayer: AudiobookPlayerModel?
    @Published private(set) var closeToken = UUID()
    @Published private(set) var isFullPlayerVisible = false

    private init() {}

    func player(for audiobook: Audiobook) -> AudiobookPlayerModel {
        if let currentPlayer, currentPlayer.audiobook.id == audiobook.id { return currentPlayer }
        return AudiobookPlayerModel(audiobook: audiobook)
    }

    func activate(_ player: AudiobookPlayerModel) {
        AudiobookStore.markPlayed(player.audiobook.id)
        guard currentPlayer !== player else { return }
        if currentPlayer?.audiobook.id != player.audiobook.id {
            currentPlayer?.stop()
        }
        currentPlayer = player
    }

    func setFullPlayerVisible(_ isVisible: Bool) {
        isFullPlayerVisible = isVisible
    }

    func close() {
        currentPlayer?.stop()
        currentPlayer = nil
        closeToken = UUID()
    }
}

struct MiniAudiobookPlayer: View {
    @ObservedObject private var playback = AudiobookPlaybackStore.shared
    @State private var showsFullPlayer = false

    var body: some View {
        Group {
            if let player = playback.currentPlayer, !playback.isFullPlayerVisible {
                MiniAudiobookPlayerContent(player: player, showsFullPlayer: $showsFullPlayer)
            }
        }
        .sheet(isPresented: $showsFullPlayer) {
            if let player = playback.currentPlayer {
                NavigationStack {
                    AudiobookPlayerView(player: player)
                }
            }
        }
        .onChange(of: playback.closeToken) { _, _ in
            showsFullPlayer = false
        }
    }
}

private struct MiniAudiobookPlayerContent: View {
    @ObservedObject var player: AudiobookPlayerModel
    @ObservedObject private var playback = AudiobookPlaybackStore.shared
    @Binding var showsFullPlayer: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showsFullPlayer = true
            } label: {
                HStack(spacing: 12) {
                    if let data = player.audiobook.coverData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "headphones.circle.fill").font(.title2).foregroundStyle(.indigo)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.audiobook.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("Chapter \(player.chapterIndex + 1) · \(player.currentChapterTitle)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        ProgressView(value: player.progress)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(player.isPlaying ? "Pause audiobook" : "Play audiobook")

            Button {
                showsFullPlayer = false
                playback.close()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close mini player")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

private struct BookmarkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    let save: (String) -> Void

    var body: some View {
        NavigationStack {
            Form { TextField("Note (optional)", text: $note) }
                .navigationTitle("Add Bookmark")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(note); dismiss() } }
                }
        }
        .presentationDetents([.medium])
    }
}

@MainActor final class AudiobookPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    let audiobook: Audiobook
    @Published var chapterIndex = 0 {
        didSet {
            guard oldValue != chapterIndex else { return }
            let shouldResume = isPlaying
            savePosition(for: oldValue)
            loadChapter(autoplay: shouldResume)
        }
    }
    @Published var progress = 0.0
    @Published private(set) var elapsed = 0.0
    @Published private(set) var isPlaying = false
    @Published var speed: Float = 1.0 {
        didSet {
            audioPlayer?.rate = speed
            UserDefaults.standard.set(speed, forKey: speedKey)
            updateNowPlayingInfo()
        }
    }
    @Published private(set) var sleepTimerRemaining: TimeInterval?
    @Published private(set) var bookmarks: [AudiobookBookmark]
    private var audioPlayer: AVAudioPlayer?
    private var sleepTimer: Timer?
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private var wasPlayingBeforeInterruption = false
    private var isObservingAudioNotifications = false
    private var lastPositionSave = Date.distantPast
    private var speedKey: String { "audiobook-\(audiobook.id.uuidString)-speed" }
    var currentChapterTitle: String {
        guard audiobook.chapters.indices.contains(chapterIndex) else { return "Audiobook" }
        return audiobook.chapters[chapterIndex].title
    }

    init(audiobook: Audiobook) {
        self.audiobook = audiobook
        self.bookmarks = AudiobookStore.bookmarks(for: audiobook.id)
        super.init()
        if let savedSpeed = UserDefaults.standard.object(forKey: speedKey) as? NSNumber {
            speed = savedSpeed.floatValue
        } else {
            speed = 1
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        configureRemoteCommands()
        registerAudioNotifications()
        loadChapter()
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
        sleepTimer?.invalidate()
    }
    func toggle() {
        guard let audioPlayer else { return }
        if isPlaying {
            audioPlayer.pause()
            savePosition()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            guard audioPlayer.play() else {
                updateNowPlayingInfo()
                return
            }
            isPlaying = true
        }
        updateNowPlayingInfo()
    }
    func stop() {
        savePosition()
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
        audioPlayer?.stop()
        isPlaying = false
        updateNowPlayingInfo()
    }
    func previousChapter() { guard chapterIndex > 0 else { return }; chapterIndex -= 1 }
    func nextChapter() { guard chapterIndex + 1 < audiobook.chapters.count else { return }; chapterIndex += 1 }
    func skip(by seconds: TimeInterval) {
        audioPlayer?.currentTime = max(0, min(audioPlayer?.duration ?? 0, (audioPlayer?.currentTime ?? 0) + seconds))
        progress = (audioPlayer?.currentTime ?? 0) / max(1, audioPlayer?.duration ?? 1)
        savePosition()
        updateNowPlayingInfo()
    }
    func seek(toProgress value: Double) {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = value * audioPlayer.duration
        refresh()
        savePosition()
        updateNowPlayingInfo()
    }
    func previewProgress(_ value: Double) {
        progress = value
        elapsed = value * (audioPlayer?.duration ?? 0)
    }
    func refresh() {
        if let end = sleepTimer?.fireDate {
            let remaining = max(0, end.timeIntervalSinceNow)
            sleepTimerRemaining = remaining
        }
        guard let audioPlayer else { return }
        elapsed = audioPlayer.currentTime
        progress = audioPlayer.duration > 0 ? audioPlayer.currentTime / audioPlayer.duration : 0
        if isPlaying, Date().timeIntervalSince(lastPositionSave) >= 5 {
            savePosition()
            lastPositionSave = Date()
        }
        updateNowPlayingInfo()
    }
    var elapsedText: String { format(elapsed) }
    var remainingText: String { format(max(0, (audioPlayer?.duration ?? 0) - elapsed)) }
    var sleepTimerLabel: String {
        guard let remaining = sleepTimerRemaining else { return "Sleep Timer" }
        return "Sleep \(max(1, Int(ceil(remaining / 60))))m"
    }
    func formatTime(_ seconds: TimeInterval) -> String { format(seconds) }
    func addBookmark(note: String) {
        bookmarks.append(AudiobookBookmark(id: UUID(), chapterIndex: chapterIndex, time: elapsed, note: note, createdAt: Date()))
        AudiobookStore.saveBookmarks(bookmarks, for: audiobook.id)
    }
    func jump(to bookmark: AudiobookBookmark) {
        guard audiobook.chapters.indices.contains(bookmark.chapterIndex) else { return }
        chapterIndex = bookmark.chapterIndex
        audioPlayer?.currentTime = min(bookmark.time, audioPlayer?.duration ?? bookmark.time)
        refresh()
    }
    func setSleepTimer(_ duration: TimeInterval?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
        guard let duration else { return }
        sleepTimer = Timer.scheduledTimer(timeInterval: duration, target: self, selector: #selector(sleepTimerFired), userInfo: nil, repeats: false)
        sleepTimerRemaining = duration
    }
    @objc private func sleepTimerFired() {
        audioPlayer?.pause()
        isPlaying = false
        sleepTimer = nil
        sleepTimerRemaining = nil
        savePosition()
        updateNowPlayingInfo()
    }

    private func configureRemoteCommands() {
        removeAllRemoteCommandTargets()
        remoteCommandCenter.playCommand.addTarget(self, action: #selector(remotePlay))
        remoteCommandCenter.pauseCommand.addTarget(self, action: #selector(remotePause))
        remoteCommandCenter.skipBackwardCommand.preferredIntervals = [15]
        remoteCommandCenter.skipForwardCommand.preferredIntervals = [30]
        remoteCommandCenter.skipBackwardCommand.addTarget(self, action: #selector(remoteSkipBackward))
        remoteCommandCenter.skipForwardCommand.addTarget(self, action: #selector(remoteSkipForward))
    }

    private func removeRemoteCommandTargets() {
        remoteCommandCenter.playCommand.removeTarget(self)
        remoteCommandCenter.pauseCommand.removeTarget(self)
        remoteCommandCenter.skipBackwardCommand.removeTarget(self)
        remoteCommandCenter.skipForwardCommand.removeTarget(self)
    }

    private func removeAllRemoteCommandTargets() {
        remoteCommandCenter.playCommand.removeTarget(nil)
        remoteCommandCenter.pauseCommand.removeTarget(nil)
        remoteCommandCenter.skipBackwardCommand.removeTarget(nil)
        remoteCommandCenter.skipForwardCommand.removeTarget(nil)
    }

    @objc private func remotePlay(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard !isPlaying else { return .success }
        toggle()
        return .success
    }

    @objc private func remotePause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard isPlaying else { return .success }
        toggle()
        return .success
    }

    @objc private func remoteSkipBackward(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        skip(by: -15)
        return .success
    }

    @objc private func remoteSkipForward(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        skip(by: 30)
        return .success
    }

    private func updateNowPlayingInfo() {
        guard audiobook.chapters.indices.contains(chapterIndex), let audioPlayer else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: audiobook.chapters[chapterIndex].title,
            MPMediaItemPropertyAlbumTitle: audiobook.title,
            MPMediaItemPropertyArtist: audiobook.author,
            MPMediaItemPropertyPlaybackDuration: audioPlayer.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audioPlayer.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0
        ]
        if let coverData = audiobook.coverData, let image = UIImage(data: coverData) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func registerAudioNotifications() {
        guard !isObservingAudioNotifications else { return }
        isObservingAudioNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        // AVAudioSession interruption values are 1 for began and 0 for ended.
        if typeValue == 1 {
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying { toggle() }
        } else if typeValue == 0, wasPlayingBeforeInterruption {
            try? AVAudioSession.sharedInstance().setActive(true)
            wasPlayingBeforeInterruption = false
            toggle()
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable, isPlaying { toggle() }
    }

    private func loadChapter(autoplay: Bool = false) {
        guard audiobook.chapters.indices.contains(chapterIndex) else { return }
        let url = AudiobookStore.audioDirectory.appending(path: audiobook.chapters[chapterIndex].fileName)
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.enableRate = true
        audioPlayer?.rate = speed
        audioPlayer?.prepareToPlay()
        let saved = UserDefaults.standard.double(forKey: key(for: chapterIndex))
        audioPlayer?.currentTime = min(saved, audioPlayer?.duration ?? 0)
        elapsed = audioPlayer?.currentTime ?? 0
        progress = (audioPlayer?.duration ?? 0) > 0 ? (audioPlayer?.currentTime ?? 0) / (audioPlayer?.duration ?? 1) : 0
        isPlaying = autoplay && (audioPlayer?.play() ?? false)
        updateNowPlayingInfo()
    }
    private func savePosition(for chapter: Int? = nil, time: TimeInterval? = nil) {
        let index = chapter ?? chapterIndex
        guard audiobook.chapters.indices.contains(index) else { return }
        UserDefaults.standard.set(time ?? audioPlayer?.currentTime ?? 0, forKey: key(for: index))
    }
    private func key(for chapter: Int) -> String { AudiobookStore.positionKey(for: audiobook.id, chapter: chapter) }
    private func format(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        savePosition(for: chapterIndex, time: player.duration)
        if chapterIndex + 1 < audiobook.chapters.count {
            chapterIndex += 1
        } else {
            isPlaying = false
        }
        updateNowPlayingInfo()
    }
}
