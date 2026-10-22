# Core Loops: Find & Keep, Make & Share

Builds on M1 (Browse), M2 (Interact), and Search. Still Stage 1: no server and no external APIs.

## The two loops

**Loop 1: Find & Keep.** Search for a collection → open it, or favorite it straight from the results → find it later in Favorites, including after relaunching the app.

**Loop 2: Make & Share.** Create a collection with a title, a label (tag), a description, and places → it's published to Explore → share it with the system share sheet → someone opens the link and lands on that collection's map, where they can favorite it → the author can edit or delete it later.

## Decisions

- **Sharing without a server:** a share link carries the whole collection (ID, title, tag, author, description, and place IDs) encoded in the URL: `daviscollections://collection?data=<base64url JSON>`. Every place is bundled, so any copy of the app can rebuild the collection from the link. In Stage 2, the backend can shorten this to `…/collection/<id>` without changing any views.
- **Opening a link:** if the collection already exists on the device (a seeded collection or one already received), the app opens it. Otherwise it saves the collection to the device's received collections and opens it. Place IDs the app doesn't know are dropped; a link with no known places shows an error.
- **Places can be bundled, from Apple Maps, or a dropped pin** (changed 2026-10-14, at the user's request). The picker searches bundled places first, then Apple Maps (`MKLocalSearch`, focused on Davis) for places like a McDonald's. For somewhere too new for Apple Maps, you drop a pin; its address fills in by reverse geocoding and can be edited. Added places have no rating and show "Not yet rated". They're saved on the device only when a collection that uses them is published. Share links embed their details, since the recipient's app doesn't have them, and an embedded place can never replace a bundled one. Apple Maps search needs a network connection; dropping a pin still works offline, minus the address lookup.
- **Label = tag.** The editor suggests existing tags and accepts a new one. A new tag gets the default style.
- **Published collections are public on the device:** like comments, a collection made by any user, or received by link, shows in Explore for everyone, newest first, ahead of the seeded ones.
- **Only the author can edit or delete.** Creating a collection requires signing in (from `Human_made.md`: uploading requires an account). A guest who taps New Collection signs in, and then the editor opens.
- **Persistence stays backward compatible:** new fields decode as empty when missing, so an existing saved file still loads.

## Architecture

| Piece | Responsibility |
|---|---|
| `CollectionLink` (new) | Builds and parses share URLs. Pure, unit-tested. |
| `UserStore` | `UserData.collections` (authored) and `SavedUserState.receivedCollections`. `saveCollection(_ draft:)`, `deleteCollection(_:)`, `receive(_:)`, and `catalog(from:)`, which merges published collections into the seeded catalog. |
| `CollectionDraft` (new) | The editor's state plus validation: title 3–60 characters, tag 2–24, description up to 280, at least one place. |
| `Catalog` | `adding(_:)` to merge collections, `collection(id:)`, `allLocations`, and `tags`. |
| `AppRouter` (new) | Selected tab, the Explore navigation path, and the New Collection sheet. Handles `onOpenURL`. |
| `CollectionEditor` + `PlacePicker` (new) | The create and edit form, with a live map preview of the chosen places and a searchable multi-select place list. |

Presentation rules (one sheet per presenter):
- New Collection is presented from the root, after the sign-in sheet has finished dismissing.
- Edit is presented from the map screen, through the same `.sheet(item:)` that already swaps between the location popup and Comments.

## UI changes

- **Explore:** a **+** toolbar button (New Collection). Holding down a card opens a menu with Favorite/Unfavorite and Share.
- **Collection map:** a **Share** button in the toolbar. For the author, an **Edit** button that opens the editor, which also has Delete.
- **Profile:** a **My Collections** section listing the user's collections, plus a New Collection button.
- **Card covers** are map snapshots keyed by place IDs, so editing a collection's places redraws its cover.

## Build order
1. Model and store changes, `CollectionLink`, and `CollectionDraft`, with unit tests
2. Merged catalog everywhere: Explore, Favorites, Search, and map destinations
3. `CollectionEditor` and `PlacePicker`, plus New Collection from Explore and Profile, with the sign-in gate
4. Share button, card menu, URL scheme registration, and `onOpenURL` routing
5. Edit and delete for authors
6. UI tests for both loops, then the full suite

## Done when
- [x] Loop 1 runs end to end as a guest who signs in partway through: search → favorite from the card menu → the collection is in Favorites → it's still there after relaunch.
- [x] Loop 2 runs end to end: New Collection → title, new label, description, 3 places → Save → the map opens → Share opens the share sheet with a link → the collection is first in Explore and searchable by its label.
- [x] Opening a share link for a collection not on the device opens its map; favoriting it puts it in Favorites.
- [x] The author can edit the title, label, and places, and every screen reflects the change. Delete removes it everywhere. Other users see no Edit button.
- [x] Invalid drafts can't be saved, and the editor says why.
- [x] Unit and UI tests pass, including the existing M1, M2, and Search suites.
