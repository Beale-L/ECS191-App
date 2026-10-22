import XCTest

/// Stage 1, Milestone 1 exit criteria 1–6, run as a guest.
final class M1BrowseUITests: XCTestCase {
    private let seed = SeedFixture.shared
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-resetUserState", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
    }

    // MARK: - Criteria

    /// 1. The app launches to Explore without asking the user to sign in.
    func test1_LaunchesToExploreAsGuest() {
        XCTAssertTrue(app.tabBars.buttons["Explore"].isSelected)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'sign in'")).count, 0)
        attachScreenshot("launch")
    }

    /// 2. The grid shows seeded collections with their title, tag, author, and location count.
    func test2_GridShowsEveryCollection() {
        for collection in seed.handWritten {
            let card = card(for: collection)
            scrollTo(card)
            XCTAssertTrue(card.exists, "missing card \(collection.title)")
            let count = collection.locationIDs.count
            let expectedParts = [collection.title, collection.tag, "by \(collection.authorName)", "\(count) place\(count == 1 ? "" : "s")"]
            for part in expectedParts {
                XCTAssertTrue(card.label.contains(part), "\(collection.title) card '\(card.label)' lacks '\(part)'")
            }
            // The grid is lazy, so check for unexpected cards among those loaded now.
            for visible in app.scrollViews.firstMatch.buttons.allElementsBoundByIndex {
                XCTAssertTrue(seed.collections.contains { visible.label.contains($0.title) }, "unexpected card '\(visible.label)'")
            }
        }
    }

    /// 3. Tapping any card opens its map within about 1 second, with all pins visible without panning.
    func test3_EachMapOpensQuicklyWithAllPinsVisible() {
        // XCUITest's own tap and idle-wait overhead is several seconds, so time a
        // trivial tab switch as a baseline and compare against that.
        var baselines: [TimeInterval] = []
        for _ in 0..<3 {
            let start = Date()
            app.tabBars.buttons["Favorites"].tap()
            _ = app.navigationBars["Favorites"].waitForExistence(timeout: 5)
            baselines.append(Date().timeIntervalSince(start))
            app.tabBars.buttons["Explore"].tap()
            _ = app.navigationBars["Explore"].waitForExistence(timeout: 5)
        }
        let overhead = baselines.min()!

        // A freshly booted simulator renders its first MapKit map slowly, so
        // open one map untimed before measuring.
        let warmUp = card(for: seed.collections[0])
        warmUp.tap()
        _ = app.maps.firstMatch.waitForExistence(timeout: 10)
        goBack()

        for collection in seed.handWritten {
            let locations = seed.locations(in: collection)
            let card = card(for: collection)
            let map = app.maps.firstMatch

            // Time two opens and keep the faster, to filter out simulator hiccups.
            var timings: [TimeInterval] = []
            for attempt in 0..<2 {
                scrollTo(card)
                let start = Date()
                card.tap()
                XCTAssertTrue(map.waitForExistence(timeout: 5), "\(collection.title): no map")
                XCTAssertTrue(pin(for: locations[0]).waitForExistence(timeout: 5))
                timings.append(Date().timeIntervalSince(start) - overhead)
                if attempt == 0 { goBack() }
            }
            let elapsed = timings.min()!
            XCTAssertLessThan(elapsed, 1.0, "\(collection.title) took \(elapsed)s longer than a tab switch")

            // The visible map is below the header and above the tab bar.
            let visible = map.frame.intersection(CGRect(x: 0, y: 0, width: map.frame.maxX, height: app.tabBars.firstMatch.frame.minY))
            for location in locations {
                let pin = pin(for: location)
                XCTAssertTrue(pin.exists, "\(collection.title): no pin for \(location.name)")
                XCTAssertTrue(visible.contains(pin.frame), "\(collection.title): \(location.name) at \(pin.frame) is outside \(visible)")
            }
            attachScreenshot("map-\(collection.title)")
            goBack()
        }
    }

    /// 4. Tapping any pin opens the popup with name, address, and rating; every location is reachable.
    ///
    /// Pins that overlap a neighbor at the fitted zoom level are reached by
    /// zooming in, as a user would. They're reported in an attachment rather
    /// than failing the test.
    func test4_EveryPinOpensItsPopup() {
        var neededZoom: [String] = []
        for collection in seed.handWritten {
            let card = card(for: collection)
            scrollTo(card)
            card.tap()
            XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))

            for location in seed.locations(in: collection) {
                dismissSheetIfShown()
                app.navigationBars.buttons["Show All"].tap()
                sleep(1)
                let pin = pin(for: location)
                XCTAssertTrue(pin.waitForExistence(timeout: 3), "no pin for \(location.name)")
                pin.tap()
                XCTAssertTrue(grabber.waitForExistence(timeout: 3), "\(location.name): sheet didn't open")
                XCTAssertEqual(grabber.value as? String, "Half screen", "\(location.name): sheet isn't at medium height")

                if sheetTitle() != location.name {
                    let shown = sheetTitle() ?? "nothing"
                    guard zoomInAndTap(location) else {
                        XCTFail("\(collection.title) › \(location.name): unreachable, tapping its pin shows \(shown)")
                        continue
                    }
                    neededZoom.append("\(collection.title) › \(location.name) (direct tap showed \(shown))")
                }

                XCTAssertTrue(app.staticTexts[location.address].exists, "\(location.name): address missing")
                let rating = "Rated \(String(format: "%.1f", location.rating)) out of 5, \(location.reviewCount.formatted()) reviews"
                XCTAssertTrue(app.otherElements[rating].exists, "\(location.name): expected '\(rating)'")
                XCTAssertTrue(app.buttons["Open in Maps"].exists, "\(location.name): no Open in Maps button")
            }
            dismissSheetIfShown()
            goBack()
        }

        let report = XCTAttachment(string: neededZoom.isEmpty ? "None" : neededZoom.joined(separator: "\n"))
        report.name = "Pins that needed zooming in"
        report.lifetime = .keepAlways
        add(report)
    }

    /// Tapping another pin swaps the sheet's content without closing it; tapping
    /// the map or swiping down dismisses it.
    func test4b_SheetSwapsAndDismisses() {
        let collection = seed.collection(titled: "Best Parks in Davis")
        let card = card(for: collection)
        scrollTo(card)
        card.tap()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        // Only a strip of map stays visible above the half-height sheet. Find
        // two pins at about the same height and drag the map to center them in it.
        let sheetTop = app.frame.height * 0.45
        let pins = seed.locations(in: collection).map { ($0, pin(for: $0)) }
        let pairs = pins.flatMap { a in pins.map { (a, $0) } }.filter { a, b in
            abs(a.1.frame.midY - b.1.frame.midY) < 40 && b.1.frame.midX - a.1.frame.midX > 60
        }
        guard let ((first, firstPin), (second, secondPin)) = pairs.first else {
            attachScreenshot("swap-setup")
            return XCTFail("no two pins sit side by side")
        }
        // Drag near the right edge: the left edge is the system swipe-back
        // area. One drag can fall short, so repeat until the pins are in place.
        let targetY = (map.frame.minY + sheetTop) / 2
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let dragX = map.frame.maxX - 12
        for _ in 0..<3 {
            let pairY = (firstPin.frame.midY + secondPin.frame.midY) / 2
            guard abs(pairY - targetY) > 15 else { break }
            origin.withOffset(CGVector(dx: dragX, dy: pairY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: dragX, dy: targetY)), withVelocity: .slow, thenHoldForDuration: 0.3)
            sleep(1)
        }
        for pin in [firstPin, secondPin] {
            XCTAssertTrue(pin.frame.minY > map.frame.minY && pin.frame.maxY < sheetTop, "pin at \(pin.frame) isn't above the sheet")
        }

        firstPin.tap()
        XCTAssertTrue(grabber.waitForExistence(timeout: 3))
        XCTAssertEqual(sheetTitle(), first.name)

        secondPin.tap()
        sleep(1)
        XCTAssertTrue(grabber.exists, "sheet closed instead of swapping")
        XCTAssertEqual(sheetTitle(), second.name, "sheet didn't swap to \(second.name)")

        // Tap empty map in the top-left corner, away from any pin.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.03)).tap()
        XCTAssertTrue(waitUntilGone(grabber), "tapping the map didn't dismiss the sheet")

        firstPin.tap()
        XCTAssertTrue(grabber.waitForExistence(timeout: 3))
        dismissSheetIfShown()
    }

    /// 5. Going back returns to the grid at the same scroll position.
    func test5_BackKeepsScrollPosition() {
        let card = card(for: seed.handWritten.last!)
        scrollTo(card)
        let before = card.frame

        card.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        goBack()
        sleep(1)
        XCTAssertEqual(card.frame.minY, before.minY, accuracy: 1, "scroll position changed after Back")

        card.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.15))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)))
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 3))
        sleep(1)
        XCTAssertEqual(card.frame.minY, before.minY, accuracy: 1, "scroll position changed after swipe back")
    }

    /// 6. Open in Maps launches Apple Maps at the correct place.
    func test6_OpenInMapsLaunchesAppleMaps() {
        let collection = seed.collection(titled: "Best Parks in Davis")
        let location = seed.locations(in: collection)[0]
        let card = card(for: collection)
        scrollTo(card)
        card.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        pin(for: location).tap()
        XCTAssertTrue(app.buttons["Open in Maps"].waitForExistence(timeout: 3))
        app.buttons["Open in Maps"].tap()

        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 15), "Apple Maps didn't open")
        let placeName = maps.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", location.name)).firstMatch

        // Get past Maps' first-run screens, which can appear a few seconds after launch.
        let deadline = Date().addingTimeInterval(20)
        while !placeName.exists && Date() < deadline {
            let firstRunButtons = ["Continue", "Not Now", "Allow Once", "Don't Allow", "Close"]
            if let title = firstRunButtons.first(where: { maps.buttons[$0].exists && maps.buttons[$0].isHittable }) {
                maps.buttons[title].tap()
            }
            sleep(1)
        }
        attachScreenshot("apple-maps")
        XCTAssertTrue(placeName.waitForExistence(timeout: 10), "Apple Maps doesn't show '\(location.name)'")
        app.activate()
    }

    // MARK: - Helpers

    private var grabber: XCUIElement { app.buttons["Sheet Grabber"] }

    private func card(for collection: SeedFixture.Collection) -> XCUIElement {
        app.scrollViews.firstMatch.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", collection.title)).firstMatch
    }

    private func pin(for location: SeedFixture.Location) -> XCUIElement {
        app.otherElements["AnnotationContainer"].otherElements[location.name]
    }

    /// Scrolls the grid until the element is fully above the tab bar.
    private func scrollTo(_ element: XCUIElement) {
        let tabBarTop = app.tabBars.firstMatch.frame.minY
        for _ in 0..<6 where !(element.exists && element.isHittable && element.frame.maxY < tabBarTop) {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
    }

    private func goBack() {
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 3))
    }

    /// The first line of text in the location sheet, which is the location's name.
    private func sheetTitle() -> String? {
        let grabberY = grabber.frame.minY
        return app.staticTexts.allElementsBoundByIndex
            .first { $0.frame.minY > grabberY && $0.frame.minY < grabberY + 60 }?
            .label
    }

    /// Double-taps the pin to zoom in, up to three times, until tapping it opens its own sheet.
    private func zoomInAndTap(_ location: SeedFixture.Location) -> Bool {
        for _ in 0..<3 {
            dismissSheetIfShown()
            let pin = pin(for: location)
            pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
            sleep(1)
            pin.tap()
            if grabber.waitForExistence(timeout: 3), sheetTitle() == location.name { return true }
        }
        return false
    }

    /// Drags the grabber down to dismiss. A swipe on the grabber can register as
    /// a tap, which expands the sheet instead.
    private func dismissSheetIfShown() {
        guard grabber.exists else { return }
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(waitUntilGone(grabber), "sheet didn't dismiss on swipe down")
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline { usleep(200_000) }
        return !element.exists
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
