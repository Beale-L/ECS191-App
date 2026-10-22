# Stage 1, Milestone 2: Interact

Builds on M1 (Browse), which passes exit criteria 1–6. See `Stage1_Plan.md` for the full Stage 1 scope.

## Goal

A guest can still browse everything, but liking, disliking, favoriting, or posting a comment asks them to sign in first, and then the action they tapped goes through. All of it persists on the device. M2 is complete when exit criteria 7–14 in `Stage1_Plan.md` pass.

## Decisions

- **One source of truth:** a new `@Observable` `UserStore` holds all user state. Views read from it and never write to disk themselves.
- **Per-user data:** state is stored by username (`[username: UserData]`). Signing out returns to guest mode; signing back in with the same name restores that user's reactions and favorites.
- **Comments are public:** a posted comment stays visible to everyone after its author signs out.
- **Counts are derived, never mutated:** the like count shown is `likeCount + (my reaction == .like ? 1 : 0)`, and the same goes for dislikes. Seed data is never written to. This keeps Like/Dislike mutually exclusive by construction, and keeps the Stage 2 swap to a backend simple.
- **Persistence:** a JSON file in Application Support, written after every change, behind a small `UserStatePersistence` protocol so tests can use an in-memory version.
- **Auth:** originally a local mock (username only). Since 2026-10-14, accounts have passwords: Sign In and Create Account are separate modes; passwords are at least 8 characters and stored only as salted PBKDF2-SHA256 hashes in the Keychain; usernames are case-insensitive; and a wrong username or password gets one generic error. Accounts made before passwords keep their data when claimed with Create Account. UI tests can still skip sign-in with `-signedInAs` in debug builds.

## Architecture

### `UserStore`
```
UserStore {
  username: String?                       // nil = guest
  data: [username: UserData]              // persisted
  pending: PendingAction?                 // not persisted
}
UserData { reactions: [collectionID: like | dislike],
           favorites: Set<collectionID>,
           comments: [Comment] }
```

### Auth gate
```swift
enum PendingAction { case react(id, Reaction), favorite(id), postComment(id, text) }
func perform(_ action: PendingAction)   // runs it if signed in, otherwise stores it and shows sign-in
```
- After a successful sign-in, the stored action is applied (criterion 8).
- On cancel, it's discarded and nothing changes (criterion 7).
- **Watch out:** SwiftUI shows only one sheet per presenting view. When a guest taps Post inside the Comments sheet, sign-in must be presented from the Comments sheet, not the root, or it silently fails to appear. Use a reusable `.signInGate()` modifier, applied at the root and inside the Comments sheet.

### Seed comments
- Add a `comments` array to `seed.json` and a `Comment` model (`id, collectionID, authorName, text, createdAt`, ISO 8601 dates). Add `catalog.comments(for:)`.
- A few comments per collection, with one collection left with none (an edge case from `Stage1_Plan.md`).
- The list a user sees is seed comments plus all locally posted comments, newest first.

## Scope

| Area | Change |
|---|---|
| `CollectionMapView` | Replace the header's static 👍/👎 counts with an **action bar**: Like and Dislike (with counts), Favorite, and Comments (with count). The location popup and Comments share one `.sheet(item:)`, so opening Comments swaps the sheet cleanly. Every location shares one sheet identity, so tapping another pin still swaps the content without closing. |
| `CommentsSheet` (new) | Newest-first list, a "No comments yet" empty state, and a text field with a Post button. Guests can read; Post asks a guest to sign in and keeps their draft. |
| `SignInSheet` (new) | Username field: trimmed, 3–20 characters, letters, digits, and `_`, with inline errors. |
| `CollectionGrid` | Move it out of `ExploreView` so Favorites can reuse it. Card like counts use the derived count. |
| `FavoritesView` | Guest: a prompt with a Sign In button. Signed in: the grid filtered to favorites, or "No favorites yet" when empty. It gets its own navigation stack, so cards open the map. |
| `ProfileView` | Guest: a Sign in / Sign up button. Signed in: username, favorite and comment counts, and Sign out with a confirmation. |

## Out of scope (Stage 2)
- Deleting or editing comments
- Real accounts, a server, and syncing across devices
- Creating or uploading collections

## Build order
1. `UserStore`, persistence, and per-user data, with unit tests
2. `SignInSheet`, the pending-action flow, and `.signInGate()`
3. Action bar: Like, Dislike, Favorite
4. Seed comments and `CommentsSheet`
5. Favorites and Profile tabs
6. UI tests for criteria 7–12, then the criterion 13 quality pass (dark mode; iPhone SE and Pro Max) → **M2 check**

## Tests

**Unit tests (`YelpCloneTests`)**, covering criterion 14 and the store logic:
- Like/dislike toggling: like → like clears it; like → dislike switches it; derived counts follow.
- A pending action is applied after sign-in and discarded on cancel.
- Persistence round-trip; sign-out returns to guest; data is kept per user.
- Comments sort newest first; every seed comment references a real collection; at least one collection has no comments.

**UI tests (`YelpCloneUITests`)**, covering criteria 7–12:
- Launch arguments (debug builds only): `-resetUserState YES` gives each test a fresh install, and `-signedInAs <name>` skips sign-in where it isn't under test. The reset flag takes a value because `UserDefaults` reads arguments in `-key value` pairs.
- Criterion 12: perform the actions, `terminate()` and relaunch without `-resetUserState`, then check that sign-in, reactions, favorites, and comments are all still there. Then sign out and confirm browsing still works.
