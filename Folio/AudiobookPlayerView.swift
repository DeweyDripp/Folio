import AVFoundation
import Combine
import SwiftUI

struct AudiobookPlayerView: View {
    let audiobook: Audiobook
    @StateObject private var player: AudiobookPlayerModel

    init(audiobook: Audiobook) {
        self.audiobook = audiobook
        _player = StateObject(wrappedValue: AudiobookPlayerModel(audiobook: audiobook))
    }

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "headphones.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(.indigo)
            Text(audiobook.title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(audiobook.author).foregroundStyle(.secondary)
            Picker("Chapter", selection: $player.chapterIndex) {
                ForEach(Array(audiobook.chapters.enumerated()), id: \.offset) { index, chapter in
                    Text(chapter.title).tag(index)
                }
            }
            .pickerStyle(.menu)
            Slider(value: $player.progress, in: 0...1)
            HStack(spacing: 40) {
                Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }.font(.title2)
                Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill") }.font(.system(size: 64))
                Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30") }.font(.title2)
            }
        }
        .padding(32)
        .navigationTitle("Audiobook")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }
}

@MainActor final class AudiobookPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    let audiobook: Audiobook
    @Published var chapterIndex = 0 { didSet { if oldValue != chapterIndex { loadChapter() } } }
    @Published var progress = 0.0
    @Published private(set) var isPlaying = false
    private var audioPlayer: AVAudioPlayer?

    init(audiobook: Audiobook) { self.audiobook = audiobook; super.init(); loadChapter() }
    func toggle() {
        if isPlaying { audioPlayer?.pause() } else { audioPlayer?.play() }
        isPlaying.toggle()
    }
    func stop() { audioPlayer?.stop() }
    func skip(by seconds: TimeInterval) { audioPlayer?.currentTime = max(0, min(audioPlayer?.duration ?? 0, (audioPlayer?.currentTime ?? 0) + seconds)); progress = (audioPlayer?.currentTime ?? 0) / max(1, audioPlayer?.duration ?? 1) }
    private func loadChapter() {
        guard audiobook.chapters.indices.contains(chapterIndex) else { return }
        let url = AudiobookStore.audioDirectory.appending(path: audiobook.chapters[chapterIndex].fileName)
        audioPlayer = try? AVAudioPlayer(contentsOf: url); audioPlayer?.delegate = self; audioPlayer?.prepareToPlay(); progress = 0; isPlaying = false
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { if chapterIndex + 1 < audiobook.chapters.count { chapterIndex += 1; audioPlayer?.play(); isPlaying = true } else { isPlaying = false } }
}
