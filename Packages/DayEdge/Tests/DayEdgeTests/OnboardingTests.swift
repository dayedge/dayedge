import XCTest
@testable import Shell
@testable import Domain

final class OnboardingFlowTests: XCTestCase {
    func testStepsRunInOrderAndStopAtBothEnds() {
        var flow = OnboardingFlow()
        XCTAssertEqual(flow.step, .welcome)
        XCTAssertFalse(flow.canGoBack)
        flow.back()
        XCTAssertEqual(flow.step, .welcome)
        var seen = [flow.step]
        for _ in 0..<10 { flow.next(); if seen.last != flow.step { seen.append(flow.step) } }
        XCTAssertEqual(seen, [.welcome, .calendar, .reminders, .weather, .ready])
        XCTAssertEqual(flow.position, 5)
        XCTAssertEqual(OnboardingFlow.count, 5)
        flow.back()
        XCTAssertEqual(flow.step, .weather)
        XCTAssertTrue(flow.canGoBack)
    }
}

@MainActor
final class OnboardingModelTests: XCTestCase {
    private func model() -> (OnboardingModel, MockOnboardingActions) {
        let actions = MockOnboardingActions(pause: .zero)
        return (OnboardingModel(actions: actions), actions)
    }

    func testAllowingCalendarMarksItAndMovesOn() async {
        let (model, _) = model()
        await model.primary()
        XCTAssertEqual(model.step, .calendar)
        XCTAssertEqual(model.primaryTitle, "Allow Calendar Access")
        await model.primary()
        XCTAssertEqual(model.state.calendar, .granted)
        XCTAssertEqual(model.step, .reminders)
        model.back()
        XCTAssertEqual(model.primaryTitle, "Continue", "a granted step just continues")
    }

    func testNotNowSkipsRemindersWithoutAsking() async {
        let (model, _) = model()
        await model.primary()
        await model.primary()
        XCTAssertEqual(model.secondaryTitle, "Not now")
        await model.secondary()
        XCTAssertEqual(model.step, .weather)
        XCTAssertEqual(model.state.reminders, .notDetermined)
    }

    func testChoosingACityRecordsItAndOpenFinishes() async {
        let (model, actions) = model()
        for _ in 0..<3 { await model.primary() }
        XCTAssertEqual(model.step, .weather)
        await model.secondary()
        XCTAssertTrue(model.isChoosingCity, "Choose City opens the weather location sheet")
        model.cityChoiceClosed()
        XCTAssertEqual(model.step, .weather, "cancelled: stays")
        actions.savedLocation = .city(WeatherPlace(name: "Poznań", country: "Poland", latitude: 52.41, longitude: 16.93))
        model.cityChoiceClosed()
        guard case .city(let place) = model.state.weather else { return XCTFail("no city") }
        XCTAssertEqual(place.name, "Poznań")
        XCTAssertEqual(model.step, .ready)
        XCTAssertEqual(model.primaryTitle, "Open DayEdge")
        await model.primary()
        XCTAssertTrue(actions.didFinish)
    }

    /// Show Welcome Again: steps reflect what's set and never ask again.
    func testReplayShowsCurrentStateWithoutAsking() async {
        let actions = MockOnboardingActions(pause: .zero)
        let city = WeatherPlace(name: "Poznań", country: "Poland", latitude: 52.41, longitude: 16.93)
        let model = OnboardingModel(actions: actions,
                                    state: OnboardingState(calendar: .granted, reminders: .denied, weather: .city(city)))
        await model.primary()
        XCTAssertEqual(model.primaryTitle, "Continue", "Calendar already allowed")
        XCTAssertNil(model.secondaryTitle)
        await model.primary()
        XCTAssertEqual(model.step, .reminders)
        XCTAssertEqual(model.primaryTitle, "Continue")
        XCTAssertEqual(model.secondaryTitle, "Open System Settings")
        await model.secondary()
        XCTAssertEqual(actions.openedSettings, [.reminders])
        XCTAssertEqual(model.step, .reminders, "settings opened; the step stays")
        await model.primary()
        XCTAssertEqual(model.state.reminders, .denied, "Continue never asks again")
        XCTAssertEqual(model.secondaryTitle, "Change City")
        XCTAssertEqual(OnboardingPromptStep.weather(model.state).done, "Poznań, Poland")
    }
}

final class OnboardingLaunchTests: XCTestCase {
    func testOnlyFreshInstallsSeeOnboarding() {
        XCTAssertEqual(OnboardingLaunch.decide(completed: false, calendar: .notDetermined, forced: false), .show)
        XCTAssertEqual(OnboardingLaunch.decide(completed: false, calendar: .granted, forced: false), .markDoneAndSkip)
        XCTAssertEqual(OnboardingLaunch.decide(completed: false, calendar: .denied, forced: false), .markDoneAndSkip)
        XCTAssertEqual(OnboardingLaunch.decide(completed: true, calendar: .notDetermined, forced: false), .skip)
        XCTAssertEqual(OnboardingLaunch.decide(completed: true, calendar: .granted, forced: true), .show)
    }
}
