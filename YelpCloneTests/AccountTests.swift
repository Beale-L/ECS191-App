import Foundation
import Testing
@testable import YelpClone

@MainActor
struct AccountTests {
    private let persistence = InMemoryUserStatePersistence()
    private let credentials = InMemoryCredentialStore()

    /// Few PBKDF2 rounds keep tests fast; the app uses `defaultPasswordIterations`.
    private func makeStore() -> UserStore {
        UserStore(persistence: persistence, credentials: credentials, passwordIterations: 1_000)
    }

    @Test func createThenSignInWithPassword() throws {
        let store = makeStore()
        try store.createAccount(username: "alice", password: "correct horse")
        #expect(store.username == "alice")

        store.signOut()
        try store.signIn(username: "alice", password: "correct horse")
        #expect(store.username == "alice")
    }

    @Test func wrongPasswordOrUnknownUserGetsTheSameError() throws {
        let store = makeStore()
        try store.createAccount(username: "alice", password: "correct horse")
        store.signOut()

        #expect(throws: UserStore.AccountError.incorrectCredentials) { try store.signIn(username: "alice", password: "wrong horse") }
        #expect(throws: UserStore.AccountError.incorrectCredentials) { try store.signIn(username: "nobody", password: "correct horse") }
        #expect(!store.isSignedIn)
    }

    @Test func usernamesAreCaseInsensitive() throws {
        let store = makeStore()
        try store.createAccount(username: "Alice", password: "correct horse")
        store.signOut()

        try store.signIn(username: "ALICE", password: "correct horse")
        #expect(store.username == "Alice", "signs in to the account as it was created")
        store.signOut()
        #expect(throws: UserStore.AccountError.usernameTaken) { try store.createAccount(username: "alice", password: "another one") }
    }

    @Test func passwordRules() {
        #expect(UserStore.passwordError(for: "short") != nil)
        #expect(UserStore.passwordError(for: "        ") != nil, "only spaces")
        #expect(UserStore.passwordError(for: "eight ch") == nil)
        #expect(UserStore.passwordError(for: String(repeating: "x", count: 129)) != nil)

        let store = makeStore()
        #expect(throws: UserStore.AccountError.self) { try store.createAccount(username: "alice", password: "short") }
        #expect(!store.isSignedIn)
    }

    @Test func passwordsAreNeverStoredInPlainText() throws {
        let store = makeStore()
        try store.createAccount(username: "alice", password: "correct horse")

        let credential = try #require(credentials.credential(for: "alice"))
        #expect(!credential.hash.isEmpty)
        #expect(credential.salt.count == 16)
        #expect(String(data: credential.hash, encoding: .utf8) != "correct horse")
        let saved = try JSONEncoder().encode(persistence.saved)
        #expect(String(data: saved, encoding: .utf8)?.contains("correct horse") == false, "the data file never sees the password")
    }

    @Test func samePasswordGetsADifferentHashPerUser() throws {
        let store = makeStore()
        try store.createAccount(username: "alice", password: "same password")
        try store.createAccount(username: "bob", password: "same password")
        let alice = try #require(credentials.credential(for: "alice"))
        let bob = try #require(credentials.credential(for: "bob"))
        #expect(alice.salt != bob.salt)
        #expect(alice.hash != bob.hash)
    }

    @Test func signInAppliesThePendingAction() throws {
        let store = makeStore()
        try store.createAccount(username: "alice", password: "correct horse")
        store.signOut()

        store.perform(.favorite("col-brunch"))
        #expect(throws: UserStore.AccountError.incorrectCredentials) { try store.signIn(username: "alice", password: "nope nope") }
        #expect(store.pending != nil, "a failed attempt keeps the action waiting")
        try store.signIn(username: "alice", password: "correct horse")
        #expect(store.isFavorite("col-brunch"))
    }

    @Test func accountsFromBeforePasswordsCanBeClaimed() throws {
        // Data saved when a username alone was enough.
        let old = InMemoryUserStatePersistence(SavedUserState(username: nil, users: ["grace": UserData(favorites: ["col-brunch"])]))
        let store = UserStore(persistence: old, credentials: credentials, passwordIterations: 1_000)

        #expect(throws: UserStore.AccountError.needsPassword) { try store.signIn(username: "grace", password: "anything1") }
        try store.createAccount(username: "Grace", password: "now secure")
        #expect(store.username == "grace", "claims the existing account rather than making a new one")
        #expect(store.isFavorite("col-brunch"), "keeps its data")

        store.signOut()
        try store.signIn(username: "grace", password: "now secure")
        #expect(store.isFavorite("col-brunch"))
    }

    @Test func keychainStoreRoundTrips() throws {
        let keychain = KeychainCredentialStore(service: "edu.ucdavis.ecs191.YelpClone.tests.\(UUID().uuidString)")
        defer { keychain.removeAll() }
        let credential = Credential.make(username: "Alice", password: "correct horse", iterations: 1_000)

        keychain.save(credential)
        #expect(keychain.credential(for: "alice") == credential)
        #expect(keychain.credential(for: "alice")?.matches("correct horse") == true)
        #expect(keychain.credential(for: "alice")?.matches("Correct horse") == false)

        keychain.removeAll()
        #expect(keychain.credential(for: "alice") == nil)
    }
}
