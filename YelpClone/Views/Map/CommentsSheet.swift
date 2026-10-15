import SwiftUI

/// A collection's comments, newest first. Anyone can read; posting asks a
/// guest to sign in and keeps their draft until they do.
struct CommentsSheet: View {
    let collectionID: MapCollection.ID
    let comments: [Comment]

    @Environment(UserStore.self) private var user
    @State private var draft = ""

    private static let maxLength = 500

    var body: some View {
        NavigationStack {
            Group {
                if comments.isEmpty {
                    ContentUnavailableView(
                        "No Comments Yet",
                        systemImage: "bubble.left",
                        description: Text("Be the first to say something about this collection.")
                    )
                } else {
                    List(comments) { comment in
                        CommentRow(comment: comment)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { composer }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // A guest who taps Post signs in from here, since this sheet is on top.
        .signInGate()
        // Signing in from this sheet only happens via Post, and the pending
        // post runs on sign-in, so the draft has been sent.
        .onChange(of: user.isSignedIn) { _, isSignedIn in
            if isSignedIn { draft = "" }
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("CommentField")
                .onChange(of: draft) {
                    if draft.count > Self.maxLength { draft = String(draft.prefix(Self.maxLength)) }
                }
            Button("Post") {
                let text = trimmedDraft
                let wasSignedIn = user.isSignedIn
                user.perform(.postComment(collectionID, text))
                if wasSignedIn { draft = "" }
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedDraft.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct CommentRow: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(comment.authorName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(comment.text)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("CommentRow")
    }
}

#Preview {
    let seed = try! LocalCollectionStore().loadSeed()
    Color.clear.sheet(isPresented: .constant(true)) {
        CommentsSheet(collectionID: "col-best-parks", comments: seed.comments.filter { $0.collectionID == "col-best-parks" })
    }
    .environment(UserStore(persistence: InMemoryUserStatePersistence()))
}
