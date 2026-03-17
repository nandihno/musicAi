import SwiftUI

struct MashUpView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming Soon",
                systemImage: "wand.and.stars",
                description: Text("Mash Up features are on the way.")
            )
            .navigationTitle("Mash Up")
        }
    }
}
