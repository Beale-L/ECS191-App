import Foundation
import Observation

/// One user's on-device state.
struct UserData: Codable, Equatable {
    var reactions: [MapCollection.ID: Reaction] = [:]
    var favorites: Set<MapCollection.ID> = []
    var comments: [Comment] = []
    /// Collections this user made.
    var collections: [MapCollection] = []
}

/// Everything `UserStore` persists. Data is kept per username, so signing out
/// and back in with the same name restores it.
struct SavedUserState: Codable, Equatable {
    var username: String?
    var users: [String: UserData] = [:]
    /// Collections opened from share links, kept for everyone on this device.
    var receivedCollections: [MapCollection] = []
    /// Places users added from Apple Maps or by dropping a pin, plus ones that
    /// arrived in share links.
    var addedPlaces: [Location] = []
}

// Fields added after a file was saved decode as empty, so older files still load.
extension UserData {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reactions = try container.decodeIfPresent([MapCollection.ID: Reaction].self, forKey: .reactions) ?? [:]
        favorites = try container.decodeIfPresent(Set<MapCollection.ID>.self, forKey: .favorites) ?? []
        comments = try container.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        collections = try container.decodeIfPresent([MapCollection].self, forKey: .collections) ?? []
    }
}

extension SavedUserState {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        users = try container.decodeIfPresent([String: UserData].self, forKey: .users) ?? [:]
        receivedCollections = try container.decodeIfPresent([MapCollection].self, forKey: .receivedCollections) ?? []
        addedPlaces = try container.decodeIfPresent([Location].self, forKey: .addedPlaces) ?? []
    }
}

/// An action that needs a signed-in user. A guest's action waits here until
/// they sign in, then runs.
enum PendingAction: Equatable {
    case react(MapCollection.ID, Reaction)
    case favorite(MapCollection.ID)
    case postComment(MapCollection.ID, String)
}

@Observable
final class UserStore {
    private(set) var state: SavedUserState
    private(set) var pending: PendingAction?
    /// True while the sign-in sheet should be showing.
    private(set) var isRequestingSignIn = false
    /// Views that can present the sign-in sheet, most recent last. See `SignInGate`.
    var signInGates: [UUID] = []

    @ObservationIgnored private let persistence: any UserStatePersistence
    @ObservationIgnored private let credentials: any CredentialStore
    @ObservationIgnored private let passwordIterations: Int
    @ObservationIgnored private let now: () -> Date

    /// PBKDF2 rounds for new passwords. Tests pass fewer to stay fast.
    static let defaultPasswordIterations = 310_000

    init(persistence: any UserStatePersistence,
         credentials: any CredentialStore = InMemoryCredentialStore(),
         passwordIterations: Int = UserStore.defaultPasswordIterations,
         now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.credentials = credentials
        self.passwordIterations = passwordIterations
        self.now = now
        self.state = persistence.load()
    }

    // MARK: Reading

    var username: String? { state.username }
    var isSignedIn: Bool { state.username != nil }
    /// Whether anyone has signed in on this device before.
    var hasAccounts: Bool { !state.users.isEmpty }

    private var currentUser: UserData {
        state.username.flatMap { state.users[$0] } ?? UserData()
    }

    var favorites: Set<MapCollection.ID> { currentUser.favorites }

    func reaction(to collectionID: MapCollection.ID) -> Reaction? {
        currentUser.reactions[collectionID]
    }

    func isFavorite(_ collectionID: MapCollection.ID) -> Bool {
        currentUser.favorites.contains(collectionID)
    }

    /// The seeded count plus this user's like. Seed data is never changed.
    func likeCount(for collection: MapCollection) -> Int {
        collection.likeCount + (reaction(to: collection.id) == .like ? 1 : 0)
    }

    func dislikeCount(for collection: MapCollection) -> Int {
        collection.dislikeCount + (reaction(to: collection.id) == .dislike ? 1 : 0)
    }

    /// Comments posted on this device by any user, since comments are public.
    func postedComments(for collectionID: MapCollection.ID) -> [Comment] {
        state.users.values.flatMap(\.comments).filter { $0.collectionID == collectionID }
    }

    /// Seeded and posted comments together, newest first.
    func allComments(for collectionID: MapCollection.ID, seeded: [Comment]) -> [Comment] {
        (seeded + postedComments(for: collectionID)).sorted { $0.createdAt > $1.createdAt }
    }

    var postedCommentCount: Int { currentUser.comments.count }

    // MARK: Collections

    /// Collections made on this device by any user, plus ones received by
    /// link, newest first. Like comments, they're public on this device.
    var publishedCollections: [MapCollection] {
        (state.users.values.flatMap(\.collections) + state.receivedCollections)
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// The seeded catalog with published collections first and user-added places included.
    func catalog(from base: Catalog) -> Catalog {
        base.adding(publishedCollections, places: state.addedPlaces)
    }

    /// Keeps user-added places on this device. Ignores ones it already has.
    func addPlaces(_ places: [Location]) {
        let known = Set(state.addedPlaces.map(\.id))
        let new = places.filter { $0.isUserAdded && !known.contains($0.id) }
        guard !new.isEmpty else { return }
        mutate { $0.addedPlaces.append(contentsOf: new) }
    }

    /// The signed-in user's collections, newest first.
    var myCollections: [MapCollection] {
        currentUser.collections.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func isAuthor(of collectionID: MapCollection.ID) -> Bool {
        currentUser.collections.contains { $0.id == collectionID }
    }

    /// Creates a collection, or updates one the user made. Returns the saved
    /// collection, or nil if signed out, the draft is invalid, or the user
    /// isn't the author.
    @discardableResult
    func saveCollection(_ draft: CollectionDraft) -> MapCollection? {
        guard let username, draft.isValid else { return nil }
        if let id = draft.editingID, !isAuthor(of: id) { return nil }
        // Keep the new places this collection actually uses.
        addPlaces(draft.newPlaces.filter { draft.locationIDs.contains($0.id) })
        if let id = draft.editingID {
            guard let existing = currentUser.collections.first(where: { $0.id == id }) else { return nil }
            let updated = draft.collection(id: id, authorName: username, createdAt: existing.createdAt,
                                           likeCount: existing.likeCount, dislikeCount: existing.dislikeCount)
            mutateCurrentUser { user in
                if let index = user.collections.firstIndex(where: { $0.id == id }) { user.collections[index] = updated }
            }
            return updated
        }
        let created = draft.collection(id: "user-\(UUID().uuidString)", authorName: username, createdAt: now(),
                                       likeCount: 0, dislikeCount: 0)
        mutateCurrentUser { $0.collections.append(created) }
        return created
    }

    /// Deletes a collection the signed-in user made, and drops it from every
    /// user's favorites and reactions.
    func deleteCollection(_ id: MapCollection.ID) {
        guard isAuthor(of: id) else { return }
        mutate { state in
            for name in state.users.keys {
                state.users[name]?.collections.removeAll { $0.id == id }
                state.users[name]?.favorites.remove(id)
                state.users[name]?.reactions[id] = nil
            }
        }
    }

    /// Keeps a collection opened from a share link, unless this device already
    /// has it. Received collections sort as new.
    func receive(_ collection: MapCollection) {
        guard !publishedCollections.contains(where: { $0.id == collection.id }) else { return }
        var received = collection
        received.createdAt = now()
        mutate { $0.receivedCollections.append(received) }
    }

    // MARK: Gated actions

    /// Runs the action if signed in. Otherwise saves it and asks for sign-in;
    /// it runs after signing in, or is dropped on cancel.
    func perform(_ action: PendingAction) {
        if isSignedIn {
            apply(action)
        } else {
            pending = action
            isRequestingSignIn = true
        }
    }

    /// Shows the sign-in sheet with no action waiting, e.g. from the Profile tab.
    func requestSignIn() {
        pending = nil
        isRequestingSignIn = true
    }

    func cancelSignIn() {
        pending = nil
        isRequestingSignIn = false
    }

    // MARK: Account

    /// Returns a message explaining what's wrong with the username, or nil if it's valid.
    static func validationError(for username: String) -> String? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count < 3 { return "Use at least 3 characters." }
        if name.count > 20 { return "Use 20 characters or fewer." }
        if name.contains(where: { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")) }) {
            return "Use only letters, numbers, and underscores."
        }
        return nil
    }

    static let passwordLength = 8...128

    /// Returns a message explaining what's wrong with a new password, or nil if it's acceptable.
    static func passwordError(for password: String) -> String? {
        if password.count < passwordLength.lowerBound { return "Use at least \(passwordLength.lowerBound) characters." }
        if password.count > passwordLength.upperBound { return "Use \(passwordLength.upperBound) characters or fewer." }
        if password.allSatisfy(\.isWhitespace) { return "A password can't be only spaces." }
        return nil
    }

    enum AccountError: LocalizedError, Equatable {
        case invalidUsername(String)
        case invalidPassword(String)
        case usernameTaken
        case incorrectCredentials
        /// The account was made before passwords existed.
        case needsPassword

        var errorDescription: String? {
            switch self {
            case .invalidUsername(let message), .invalidPassword(let message): message
            case .usernameTaken: "That username is taken. Sign in instead, or pick another name."
            // Doesn't say which part was wrong, so it can't be used to discover usernames.
            case .incorrectCredentials: "Incorrect username or password."
            case .needsPassword: "This account was made before passwords. Choose Create Account to set one and keep its data."
            }
        }
    }

    /// The name of an account made before passwords, matched case-insensitively.
    private func passwordlessAccount(named username: String) -> String? {
        state.users.keys.first { $0.lowercased() == username.lowercased() && credentials.credential(for: $0) == nil }
    }

    /// Creates an account and signs in. A name that already has data but no
    /// password (from before passwords existed) is claimed, keeping its data.
    func createAccount(username: String, password: String) throws {
        if let message = Self.validationError(for: username) { throw AccountError.invalidUsername(message) }
        if let message = Self.passwordError(for: password) { throw AccountError.invalidPassword(message) }
        let typed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard credentials.credential(for: typed) == nil else { throw AccountError.usernameTaken }
        let name = passwordlessAccount(named: typed) ?? typed
        credentials.save(Credential.make(username: name, password: password, iterations: passwordIterations))
        beginSession(as: name)
    }

    /// Checks the password, then signs in and runs any pending action.
    func signIn(username: String, password: String) throws {
        let typed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let credential = credentials.credential(for: typed) else {
            throw passwordlessAccount(named: typed) == nil ? AccountError.incorrectCredentials : AccountError.needsPassword
        }
        guard credential.matches(password) else { throw AccountError.incorrectCredentials }
        beginSession(as: credential.username)
    }

    /// Starts a session for a verified user, then runs any pending action.
    /// Only call this after checking credentials, or from debug launch setup and tests.
    func beginSession(as username: String) {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate { state in
            state.username = name
            if state.users[name] == nil { state.users[name] = UserData() }
        }
        isRequestingSignIn = false
        if let action = pending {
            pending = nil
            apply(action)
        }
    }

    func signOut() {
        mutate { $0.username = nil }
    }

    // MARK: Applying

    private func apply(_ action: PendingAction) {
        switch action {
        case .react(let id, let reaction):
            toggle(reaction, on: id)
        case .favorite(let id):
            toggleFavorite(id)
        case .postComment(let id, let text):
            postComment(text, on: id)
        }
    }

    /// Like and Dislike are mutually exclusive; tapping the active one clears it.
    private func toggle(_ reaction: Reaction, on id: MapCollection.ID) {
        mutateCurrentUser { user in
            user.reactions[id] = user.reactions[id] == reaction ? nil : reaction
        }
    }

    private func toggleFavorite(_ id: MapCollection.ID) {
        mutateCurrentUser { user in
            if user.favorites.remove(id) == nil { user.favorites.insert(id) }
        }
    }

    private func postComment(_ text: String, on id: MapCollection.ID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let username else { return }
        let comment = Comment(id: UUID().uuidString, collectionID: id, authorName: username, text: text, createdAt: now())
        mutateCurrentUser { $0.comments.append(comment) }
    }

    private func mutateCurrentUser(_ change: (inout UserData) -> Void) {
        guard let username else { return }
        mutate { change(&$0.users[username, default: UserData()]) }
    }

    private func mutate(_ change: (inout SavedUserState) -> Void) {
        change(&state)
        persistence.save(state)
    }
}

// MARK: - Persistence

protocol UserStatePersistence {
    func load() -> SavedUserState
    func save(_ state: SavedUserState)
}

/// Stores user state as JSON in Application Support.
struct FileUserStatePersistence: UserStatePersistence {
    var url: URL = .applicationSupportDirectory.appending(path: "user-state.json")

    // Dates use the default encoding, which keeps sub-second precision.
    // `.iso8601` would round them, so a reloaded comment wouldn't match.
    func load() -> SavedUserState {
        guard let data = try? Data(contentsOf: url) else { return SavedUserState() }
        return (try? JSONDecoder().decode(SavedUserState.self, from: data)) ?? SavedUserState()
    }

    func save(_ state: SavedUserState) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            assertionFailure("Couldn't save user state: \(error)")
        }
    }

    func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}

final class InMemoryUserStatePersistence: UserStatePersistence {
    private(set) var saved: SavedUserState

    init(_ initial: SavedUserState = SavedUserState()) {
        saved = initial
    }

    func load() -> SavedUserState { saved }
    func save(_ state: SavedUserState) { saved = state }
}

// MARK: - Launch

extension UserStore {
    /// The store the app launches with. In debug builds, UI tests can pass
    /// `-resetUserState YES` for a fresh install and `-signedInAs <name>` to skip sign-in.
    static func forLaunch(defaults: UserDefaults = .standard) -> UserStore {
        let persistence = FileUserStatePersistence()
        let credentials = KeychainCredentialStore()
        #if DEBUG
        if defaults.bool(forKey: "resetUserState") {
            persistence.reset()
            // Keychain items outlive the app's files, so clear accounts too.
            credentials.removeAll()
        }
        #endif
        let store = UserStore(persistence: persistence, credentials: credentials)
        #if DEBUG
        // Skips the password for UI tests that aren't about signing in.
        if let name = defaults.string(forKey: "signedInAs") { store.beginSession(as: name) }
        #endif
        return store
    }
}
