# Stage 2: Place Cards and Live

Based on `HM_stage2.md`. Builds on Stage 1 (M1 Browse, M2 Interact, search, and the Find & Keep and Make & Share loops).

## Goal

Tapping a business in a collection opens real information about it: an About section and ratings and reviews, from Apple's place card where possible and Yelp otherwise. A new **Live** tab shows what's happening around Davis right now: events, pop-ups, and tracked sightings such as the Davis turkeys. Each post starts with a photo taken on the spot, and a post becomes **verified** once 5 other users like it.

## Decisions

- **Still no server.** Everything stays on the device, as in Stage 1. For verification, "5 other users" means 5 other accounts on this device. Live storage sits behind a protocol, like `CollectionStore`, so a server can replace it later without changing views.
- **Apple's place card first, Yelp second.** Apple's place card provides the About section, hours, photos, and ratings from Apple's review partners. Yelp's API is the fallback for businesses Apple Maps can't match. No Google APIs.
- **Raise the minimum iOS version to 18.** Apple's place card can only be shown inside an app on iOS 18 and later (`mapItemDetailSheet`, `MKMapItemDetailViewController`). Requiring iOS 18 means every user gets the card, with no iOS 17 fallback to build and test. All testing so far has been on iOS 27.
- **The Yelp key is optional and never committed.** It's read from a build setting in a local `Secrets.xcconfig` that isn't checked in. Without a key, the Yelp fallback is hidden and nothing breaks. With no server, the key ships inside the app, where someone could extract it. That's acceptable for a class project but not for a public release; Stage 3's server should hold it.
- **Photos must come from the camera.** The photo library isn't offered, so nobody can post an old picture as live. Posts record where and when the photo was taken, and they expire.
- **Verification follows the current count.** A post is verified while at least 5 accounts other than the author like it. If an unlike drops it below 5, the badge goes away.

## Part A: Place cards (Milestone 3)

### How a pin decides what to show
1. **Matched to Apple Maps:** search Apple Maps for the place's name within 150 m of its pin, using the same name-and-distance check that hides duplicates in the place picker. Places added from Apple Maps already store their Apple ID when added. Matches, and misses, are cached on the device for 30 days, so each place is looked up only once.
2. **Apple match found:** the pin opens **Apple's place card** inside the app, with About, hours, photos, ratings, and directions. The app's own sheet stays one tap away, for the collection rating and Open in Maps.
3. **No Apple match, but Yelp finds the business:** the app's sheet gains an **About** section (Yelp category, price, hours, phone, website) and **Reviews**: Yelp's rating and up to 3 review excerpts. It shows Yelp's logo and links to the business's Yelp page, as Yelp's display rules require. Yelp results are cached for up to 24 hours, which is the limit Yelp's terms allow.
4. **Neither, or offline:** the app's sheet as it works today. A pin is never a dead end.

### Data and code
- `Location.appleMapsID: String?` holds the Apple Maps identifier. It's filled in when a place is added from Apple Maps, or once a bundled place has been matched.
- `PlaceDetailsService` matches places, caches results, and returns `.apple(MKMapItem)`, `.yelp(YelpBusiness)`, or `.none`. It's a protocol, so tests can use a stub.
- `YelpClient` uses Business Search (`term` + latitude/longitude) and then the business's reviews endpoint. It does nothing when there's no key.
- `CollectionMapView` presents Apple's card with `.mapItemDetailSheet(item:)`, through the same single sheet that already swaps between the location popup, Comments, and Edit.

### What building it showed (2026-10-15)
- **Apple's in-app card has About details, not reviews.** For Temple and Pachamama it showed the photo, category, hours, and phone, with no ratings or reviews. So Yelp isn't only a fallback: the service looks up Apple and Yelp together. Apple's card shows on the **Place Card** tab, and Yelp's rating, review excerpts, and About appear on the **In This App** tab next to the app's own details. If Apple has no match, the Yelp details show on their own, as planned.
- **Apple's card lays itself out once, at the size it's created with.** Created in a half-height sheet and then expanded, it was cut off and wouldn't scroll. The sheet now opens at full height when the card is found, and rebuilds the card if it's resized.
- **The first lookup can be slow** (about 12 seconds cold on the simulator, about 1 second after that), so the app's own details show immediately with "Looking up reviews and details…".
- Not yet verified with a real key: how Yelp's current plan limits the reviews endpoint. Without review access, the business still shows, without excerpts.
- Yelp's display rules ask for their logo. The app shows "from Yelp" with a link to the business's Yelp page; add the logo from Yelp's brand kit before any public release.

## Part B: Live (Milestone 4)

### Model
```
LivePost  { id, kind: event | popUp | sighting, title, note?, trackerID?,
            authorName, photoFile, latitude, longitude,
            createdAt, expiresAt, likes: Set<username> }
Tracker   { id, name, symbol }    // seeded: Davis Turkeys, Food Trucks, Free Food on Campus
```
- `isVerified` is true when `likes` minus the author has at least 5 names.
- Durations are 1, 3, 6, or 24 hours. The defaults are 1 hour for sightings and 3 hours for events and pop-ups. Expired posts leave Live and are deleted after 7 days.
- `LiveStore` (`@Observable`) is backed by `LivePersistence`: `live.json` plus a JPEG per post in Application Support. `-resetUserState` clears Live too.

### Live tab (4th tab)
- **Map and List** views of active posts. Filter chips: All, Events, Pop-ups, and each tracker. Map pins show a photo thumbnail, and verified posts get a checkmark seal.
- **Post detail:** the photo, title, kind, how long ago it was posted and when it ends, the author, and the location on a small map. A **Like** button is gated by sign-in, like the existing actions. Progress toward verification shows as "3 of 5 to verify", and a **Verified** badge appears at 5.
- **Tracker view**, for example Davis Turkeys: the last 24 hours of sightings on a map, newest first, so you can see where the turkeys have been.

### Posting
1. Tap **+**. Guests sign in first, reusing the sign-in gate and the "do this after sign-in" pattern from New Collection.
2. **The camera opens.** There's no library option. If the device has no camera, Live explains that posting needs one.
3. After the photo: a title, the kind (and a tracker, for sightings), and how long it lasts. Location comes from the device's current position at the moment the photo is taken, with When In Use permission. If permission is denied, the poster drops a pin instead (reusing `DropPinView`).
4. **Saving:** the photo is shrunk to at most 1600 px and saved as JPEG with its metadata removed, so the file doesn't carry the camera's location or device details. The post's location is stored separately, at the precision the poster chose.

### Permissions
`NSCameraUsageDescription` and `NSLocationWhenInUseUsageDescription` are added to `YelpClone/Info.plist`, with plain explanations of why each is needed.

### Testing a camera-only feature
The simulator has no camera. In debug builds, `-fakeCamera YES` swaps in a camera stand-in that returns a generated test photo (and uses downtown Davis as the location), so UI tests can run the whole posting flow. `-seedLiveDemo YES` fills Live with sample posts and trackers for demos and tests. `-disablePlaceCards YES` keeps place cards out of tests that check the app's own popup, so they don't depend on the network. **A real iPhone check is still required** for the actual camera and location.

Found while testing: MapKit can build pin views outside SwiftUI's normal update, where the app's environment isn't available, so reading a store from the environment inside a map pin crashed the app after posting. Map pins now receive everything they need as plain values.

## Out of scope (Stage 3 or later)
- A server: syncing across devices, real multi-user verification, and keeping the Yelp key off the device
- Reporting or moderating posts, and notifications about new sightings
- Video, more than one photo per post, and editing a post after it's published

## Build order
1. Raise the deployment target to iOS 18, and confirm the existing suite still passes
2. `PlaceDetailsService` with Apple matching and its cache, plus Apple's card on pins, with unit tests → check what the card shows
3. `YelpClient`, the Yelp About and Reviews sections, attribution, and caching, with tests using stubbed responses → **M3 check**
4. `LivePost`, `Tracker`, `LiveStore`, and persistence, with unit tests (verification rules, expiry, cleanup)
5. The Live tab: map, list, filters, post detail, and likes
6. Posting: camera, the fake camera, location, the form, and stripping photo metadata
7. Trackers, demo seeding, UI tests, and a real-device check → **M4 check**

## Exit criteria

Test on the iPhone 17 simulator (iOS 27), and on a real iPhone for the camera and location.

**M3: Place cards**
- [x] 15. Tapping a pin for an established business (for example Temple Coffee Roasters or Redrum Burger) opens Apple's place card inside the app, with an About section and ratings.
- [ ] 16. A business Apple Maps can't match shows Yelp's rating, review excerpts, and About details with Yelp's logo and link, when a Yelp key is set up.
- [x] 17. With no match, no key, or no network, the pin opens the app's own sheet, as it did in Stage 1. A pin is never a dead end.
- [x] 18. Each place is looked up at most once per 30 days, and Yelp data is kept no longer than 24 hours.

**M4: Live**
- [x] 19. A Live tab shows active posts on a map and in a list. Expired posts don't appear.
- [x] 20. Posting requires signing in and taking a photo with the camera. The photo library is never offered.
- [x] 21. Each post has a location, from the device or a dropped pin, and the saved photo has no embedded metadata.
- [x] 22. Each account can like a post once, and authors can't like their own. The Verified badge appears at 5 likes from other accounts and goes away if it drops below 5.
- [x] 23. The Davis Turkeys tracker shows the last 24 hours of sightings on a map.
- [x] 24. Posts, likes, and photos survive a relaunch. `-resetUserState` clears them.

**Quality**
- [ ] 25. Unit and UI tests pass, including all Stage 1 suites, with the camera path covered by the fake camera. A real-iPhone walkthrough has been done.
