//
//  ContentView.swift
//  Folio
//
//  Created by Ryan Ramirez on 9/10/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        LibraryView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniAudiobookPlayer()
            }
    }
}

#Preview {
    ContentView()
}
