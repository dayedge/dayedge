import AppKit
import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import UI

/// Scrolls a long agenda of realistic rows through the real scroll view and
/// times it — the number row optimizations are judged by (`ROWBENCH`).
@MainActor
final class AgendaRowScrollBenchmarkTests: XCTestCase {
    private static func events(count: Int) -> [(AgendaEventModel, Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).map { n in
            let day = today.addingTimeInterval(Double(n / 4) * 86400)
            let start = day.addingTimeInterval(Double(8 + n % 4 * 2) * 3600)
            let kind = n % 6
            let multiDay = kind == 5
            let event = AgendaEventModel(
                id: "e\(n)", startTime: "10:30", endTime: "11:45",
                startDate: start, endDate: multiDay ? start.addingTimeInterval(36 * 3600) : start.addingTimeInterval(4500),
                title: kind == 1 ? "1F_Refinement_części wspólne — a longer title that wraps onto two lines" : "PZU 1f Daily \(n)",
                subtitle: kind % 2 == 0 ? "Spotkanie w aplikacji Microsoft Teams" : nil,
                status: kind == 2 ? .tentative : kind == 3 ? .cancelled : .confirmed,
                videoService: kind < 3 ? .teams : nil, hasLinkIcon: kind == 4, isRecurring: kind % 2 == 1,
                calendarName: "Calendar", videoURL: kind < 3 ? "https://teams.microsoft.com/l/meetup-join/x" : nil)
            return (event, day)
        }
    }

    func testScrollingALongAgenda() async throws {
        let rows = Self.events(count: 400)
        let view = ThemedScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.0.id) { event, day in
                    AgendaEventRowView(event: event, date: day)
                }
            }
        }
        .frame(width: 400, height: 700)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let scrollView = Self.find(NSScrollView.self, in: host) else { return XCTFail("no scroll view") }

        // Warm up, then several passes of ~1/3-screen steps like a steady
        // scroll; best and median of the passes (single runs are noisy).
        try await Task.sleep(for: .milliseconds(100))
        var averages: [Double] = []
        var total: TimeInterval = 0
        let instructionsBefore = Self.instructions()
        for _ in 0..<5 {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            host.layoutSubtreeIfNeeded()
            let start = Date()
            var steps = 0
            var y: CGFloat = 0
            while steps < 200 {
                y += 220
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                host.layoutSubtreeIfNeeded()
                steps += 1
                if y > (scrollView.documentView?.frame.height ?? 0) { break }
            }
            let elapsed = Date().timeIntervalSince(start)
            total += elapsed
            averages.append(elapsed * 1000 / Double(max(steps, 1)))
        }
        let instructions = Double(Self.instructions() - instructionsBefore) / 1_000_000
        averages.sort()
        print(String(format: "ROWBENCH %.0f M instructions · per step best %.2f ms · median %.2f ms",
                     instructions, averages[0], averages[averages.count / 2]))
        XCTAssertLessThan(total, 20, "generous bound — the printed number is what matters")
    }

    /// Instructions this process has retired — steady where wall time isn't
    /// (Low Power Mode, other load).
    private static func instructions() -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? info.ri_instructions : 0
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews { if let match = find(type, in: subview) { return match } }
        return nil
    }
}
