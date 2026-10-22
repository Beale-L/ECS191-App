# Collections (YelpClone)

An iOS app for browsing, building, and sharing collections of places around Davis: mountain biking trails, date nights, bars, animal watching spots, and more. Each collection opens on an Apple Map with a pin for every place. You can search, like, favorite, and comment on collections, save single places from any map, and make your own collections to share by link, with label autocomplete and place suggestions to help fill them in. Everything runs on the device, with no server or API keys needed.

## Quick start

```sh
git clone https://github.com/Beale-L/ECS191-App.git
cd ECS191-App
open YelpClone.xcodeproj
```

In Xcode, pick the **YelpClone** scheme and an iPhone simulator, then press **Run** (⌘R).

You can also skip the terminal: on the GitHub page, click **Code > Open with Xcode**, or **Code > Download ZIP**, unzip it, and double-click `YelpClone.xcodeproj`.

## Requirements

- A Mac with **Xcode 16 or later** (the project uses Swift 6)
- **iOS 17.0+** on the simulator or device
- An Apple ID signed in to Xcode, for running on a physical iPhone
- A paid Apple Developer Program membership, only for TestFlight or App Store distribution

If `xcodebuild` reports that the active developer directory is the Command Line Tools, point it at Xcode once:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Run in the Simulator

1. In Xcode, select the **YelpClone** scheme.
2. Pick an iPhone simulator.
3. Press **Run** (⌘R).

From the command line (use any simulator name from `xcrun simctl list devices available`):

```sh
xcodebuild -project YelpClone.xcodeproj -scheme YelpClone \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Run on an iPhone

1. Connect the iPhone by cable (or pair it over Wi-Fi in **Window > Devices and Simulators**).
2. On the phone, turn on **Settings > Privacy & Security > Developer Mode** and restart when asked.
3. In Xcode, select the **YelpClone** project > **YelpClone** target > **Signing & Capabilities**:
   - Leave **Automatically manage signing** on.
   - Set **Team** to your own Apple ID or team.
   - If Xcode says the bundle ID is taken, change **Bundle Identifier** from `edu.ucdavis.ecs191.YelpClone` to something unique, like `edu.ucdavis.ecs191.YelpClone.<yourname>`.
4. Choose your iPhone as the run destination and press **Run** (⌘R).
5. The first time, the phone may refuse to open the app. Go to **Settings > General > VPN & Device Management**, select your developer profile, and tap **Trust**.

With a free Apple ID, the app expires after 7 days; just run it from Xcode again.

## Distribute with TestFlight

This needs a paid Apple Developer Program membership.

1. In [App Store Connect](https://appstoreconnect.apple.com/), go to **Apps > +** and create a new app using the same bundle ID as the target.
2. In Xcode, increase **Version** (`MARKETING_VERSION`, currently `0.1`) or **Build** for every upload.
3. Set the run destination to **Any iOS Device (arm64)**.
4. Choose **Product > Archive**.
5. When the Organizer opens, select the archive and click **Distribute App > TestFlight & App Store** (or **TestFlight Internal Only**), then follow the prompts.
6. After processing (usually 10 to 30 minutes), the build appears under the app's **TestFlight** tab in App Store Connect. Add internal testers, or create an external group (external testing requires a short Beta App Review).
7. Testers install the **TestFlight** app on their iPhone and accept the invite.

## Running the tests

In Xcode, press **⌘U**, or from the command line (again, swap in any simulator you have):

```sh
xcodebuild test -project YelpClone.xcodeproj -scheme YelpClone \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Unit tests are in `YelpCloneTests/` and UI tests are in `YelpCloneUITests/`. The UI tests that open every map check the ten hand-written collections at the top of the grid, so a full run takes about 35 minutes on a simulator. Run only the unit tests (a few seconds) with `-only-testing:YelpCloneTests`.

## Sample data

The collections, places, and comments are bundled in `YelpClone/Data/seed.json`: 315 collections across 22 tags, built from 111 places in and around Davis (Winters, Woodland, Lake Berryessa, Sacramento). The first ten collections are hand-written and the rest are generated. Most places are real, but their coordinates are approximate, and ratings, review counts, authors, and comments are made up.

## Shared collection links

The app registers the `daviscollections://` URL scheme, so shared collection links open directly in the app once it's installed. No extra setup is needed.

## Project layout

| Path | What's there |
| --- | --- |
| `YelpClone/` | App source (models, data, SwiftUI views) |
| `YelpClone/Data/seed.json` | Bundled sample collections, places, and comments |
| `YelpCloneTests/` | Unit tests |
| `YelpCloneUITests/` | UI tests |
| `plan/` | Project docs: proposal, milestone and stage plans, notes |

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "No account for team" or "Signing requires a development team" | Pick your own Team under Signing & Capabilities. |
| "Failed to register bundle identifier" | Change the Bundle Identifier to something unique. |
| "Untrusted Developer" on the iPhone | Trust your profile under Settings > General > VPN & Device Management. |
| Simulator destination missing | Install an iOS simulator runtime in Xcode > Settings > Components. |
