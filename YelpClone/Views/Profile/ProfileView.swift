import SwiftUI

struct ProfileView: View {
    @Environment(UserStore.self) private var user
    @Environment(AppRouter.self) private var router
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profile")
                .collectionMapDestination()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let username = user.username {
            List {
                Section {
                    Label {
                        Text(username).font(.title3.weight(.semibold))
                    } icon: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title)
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    ForEach(user.myCollections) { collection in
                        NavigationLink(value: collection) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(collection.title)
                                HStack(spacing: 8) {
                                    TagChip(tag: collection.tag)
                                    Text("^[\(collection.locationIDs.count) place](inflect: true)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Button("New Collection", systemImage: "plus") {
                        router.startNewCollection(user: user)
                    }
                } header: {
                    Text("My Collections")
                } footer: {
                    if user.myCollections.isEmpty {
                        Text("Make a collection of your favorite places to share it with others.")
                    }
                }
                Section("Activity") {
                    LabeledContent("Favorites", value: user.favorites.count, format: .number)
                    LabeledContent("Comments", value: user.postedCommentCount, format: .number)
                }
                Section {
                    Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
                }
            }
            .confirmationDialog("Sign out of \(username)?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { user.signOut() }
            } message: {
                Text("Your likes, favorites, and comments stay on this device for when you sign back in.")
            }
        } else {
            ContentUnavailableView {
                Label("Browsing as Guest", systemImage: "person.crop.circle")
            } description: {
                Text("Sign in to like, favorite, and comment on collections.")
            } actions: {
                Button("Sign In / Sign Up") { user.requestSignIn() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
