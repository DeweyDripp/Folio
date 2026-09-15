import SwiftUI

struct AudiobooksLibraryView: View {
    let audiobooks: [Audiobook]
    var body: some View {
        List(audiobooks) { audiobook in
            NavigationLink { AudiobookPlayerView(audiobook: audiobook) } label: {
                Label(audiobook.title, systemImage: "headphones.circle")
            }
        }
        .navigationTitle("Audiobooks")
    }
}
