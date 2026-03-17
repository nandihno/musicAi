import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Create Playlist", systemImage: "music.note.list") {
                CreatePlaylistView()
            }

            Tab("Mash Up", systemImage: "wand.and.stars") {
                MashUpView()
            }
        }
    }
}
