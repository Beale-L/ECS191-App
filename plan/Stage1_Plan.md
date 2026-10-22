# Stage 1: Browse Collections

Based on `Human_made.md` and `Proposal.md`.

## Goal

A guest opens the app, browses a grid of user-made collections, opens one to see its locations on a map, and taps any pin to see that location's info and rating. Signing in unlocks like, dislike, favorite, and comment.

## Decisions

- **Platform:** iPhone, iOS 17+, SwiftUI and MapKit. No third-party map SDK.
- **Data:** Seed data is bundled as JSON and loaded through a `CollectionStore` protocol. Stage 1 has no server. In Stage 2 a backend implementation replaces the local store, and no views need to change.
- **Auth:** Local accounts with a username and password, kept on the device (added 2026-10-14; previously username only). Passwords are stored only as salted PBKDF2-SHA256 hashes in the Keychain. Accounts sync across devices only once the backend arrives.
- **No external APIs:** Stage 1 makes no calls to Google Maps, Yelp, or any other third-party API. Maps come from Apple's MapKit, and all place data, including ratings, is bundled in the app.
- **Ratings:** The ratings shown are seeded values. The new, fairer rating system from the proposal comes in a later stage.

## Milestones

| Milestone | Contents | Gate |
|---|---|---|
| **M1: Browse** | Navigation, Explore grid, collection map, location popup | Exit criteria 1–6 (the original "landing page is functional" criterion) |
| **M2: Interact** | Auth gate, like/dislike/favorite/comment, Favorites and Profile tabs, persistence | Exit criteria 7–14 |

Stage 1 is complete when both milestones pass.

## Scope

### Navigation
- Tab bar with three tabs: **Explore** (landing), **Favorites**, **Profile**.
- Explore uses a navigation stack: Grid → Collection map.

### Explore (landing page)
- Two-column grid of collection cards. Each card shows a cover image, title, tag chip (e.g. "Parks", "Chinese Food"), author, number of locations, and like count.
- Pull to refresh reloads from the store.
- Search bar (added after M2) filters by title, tag, author, description, or a place's name or category. Every word must match, ignoring case, accents, and apostrophes. A card that matched only by place says which place ("Includes Temple Coffee Roasters").
- Empty state ("No collections yet") and error state (message plus a Retry button).

### Collection map
- Map with one pin per location. The camera fits all pins on screen when the map opens.
- Header shows the title, tag, author, and a short description.
- Action bar: Like / Dislike (with counts), Favorite, Comments.

### Location popup
- Opens as a bottom sheet at medium height when a pin is tapped.
- Shows the name, category, address, rating (stars and review count), price level ($–$$$$), and a photo if one exists.
- **Open in Maps** button hands the location off to Apple Maps.
- Swiping down or tapping the map dismisses it. Tapping another pin swaps the content without closing the sheet.

### Interactions and auth gate
- Like and Dislike are mutually exclusive. Tapping the active one again clears it.
- Favorite adds the collection to the Favorites tab.
- Comments open as a sheet listing comments newest first. Guests can read them, but only signed-in users can post.
- When a guest taps Like, Dislike, Favorite, or Post, a sign-in sheet appears. After signing in, the action they tapped is applied.
- All user state persists on the device across launches.

### Favorites tab
- The same card grid, filtered to favorited collections. Guests see a prompt to sign in.

### Profile tab
- Guest: Sign in / Sign up button.
- Signed in: username and Sign out.

## Out of scope (later stages)
- Creating or uploading collections from the app (Stage 2, together with the backend)
- Real accounts, a server, and syncing across devices
- Writing reviews for locations, and the new rating system
- Following critics and "near me" sorting

## Data model

```
Collection  { id, title, tag, authorName, description, coverImage,
              locationIDs: [id], likeCount, dislikeCount }
Location    { id, name, category, address, latitude, longitude,
              rating: 0–5, reviewCount, priceLevel: 1–4, photo? }
Comment     { id, collectionID, authorName, text, createdAt }
UserState   { username?, reactions: [collectionID: like | dislike],
              favorites: Set<collectionID>, comments: [Comment] }   // on device
```

## Seed data
- At least 6 collections covering at least 4 different tags. Most have 5–10 locations.
- Use real Davis-area places, which fits the proposal's "near me" focus.
- Edge cases: one collection with a single location, one with 15+ locations spread across town (to test camera fit), one location with no photo, and one collection with no comments.

## Build order
1. Xcode project, tab bar shell, models, seed JSON, `LocalCollectionStore`
2. Explore grid and cards
3. Collection map with pins and camera fit
4. Location popup sheet and Open in Maps → **M1 check**
5. `UserState` store with on-device persistence, plus the mock sign-in sheet
6. Like/Dislike/Favorite and the auth gate
7. Comments sheet
8. Favorites and Profile tabs → **M2 check**

## Exit criteria

Test on the iPhone 15 simulator (iOS 17), and on a physical device if one is available.

**M1: Browse (as a guest, on a fresh install)**
- [ ] 1. The app launches to Explore without asking the user to sign in.
- [ ] 2. The grid shows every seeded collection. Each card shows its title, tag, author, and location count.
- [ ] 3. Tapping any card opens its map within about 1 second, with all pins visible without panning.
- [ ] 4. Tapping any pin opens the popup with name, address, and rating. Every seeded location can be reached this way.
- [ ] 5. Going back returns to the grid at the same scroll position.
- [ ] 6. Open in Maps launches Apple Maps at the correct place.

**M2: Interact**
- [ ] 7. As a guest, tapping Like, Dislike, Favorite, or Post comment shows the sign-in sheet, and nothing changes until the user signs in.
- [ ] 8. After signing in from that sheet, the action that triggered it is applied.
- [ ] 9. Like and Dislike are mutually exclusive, and their counts update immediately.
- [ ] 10. Favorited collections appear in the Favorites tab, and unfavoriting removes them.
- [ ] 11. A posted comment appears at the top of the list.
- [ ] 12. After quitting and relaunching the app, sign-in, reactions, favorites, and comments are all still there. After signing out, the user is back to guest mode and can still browse.

**Quality**
- [ ] 13. The full walkthrough runs with no crashes, in both light and dark mode, and nothing is clipped on iPhone SE or Pro Max.
- [ ] 14. Unit tests pass for these cases: the seed JSON decodes; every `locationID` in every collection resolves to a location; and like/dislike toggling works correctly.
