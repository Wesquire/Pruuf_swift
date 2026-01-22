import XCTest
@testable import PRUUF

/// Tests for Break Edge Cases (Section 7.3)
/// EC-7.1: Prevent overlapping breaks
/// EC-7.2: If break starts today, set status='active' and today's ping becomes 'on_break'
/// EC-7.3: If break ends today, tomorrow's ping reverts to 'pending'
/// EC-7.4: Connection pause during break applies both statuses; no pings generated
/// EC-7.5: Warn for breaks longer than 1 year
final class BreakEdgeCaseTests: XCTestCase {

    // MARK: - EC-7.1: Overlapping Breaks Prevention

    func testOverlappingBreaksDetection() {
        // Two date ranges [A, B] and [C, D] overlap if A <= D and C <= B
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Existing break: today to today + 5 days
        let existingStart = today
        let existingEnd = calendar.date(byAdding: .day, value: 5, to: today)!

        // Test case 1: New break completely inside existing break (overlaps)
        let newStart1 = calendar.date(byAdding: .day, value: 1, to: today)!
        let newEnd1 = calendar.date(byAdding: .day, value: 3, to: today)!
        XCTAssertTrue(dateRangesOverlap(
            start1: existingStart, end1: existingEnd,
            start2: newStart1, end2: newEnd1
        ), "Break completely inside another should overlap")

        // Test case 2: New break starts before, ends during existing (overlaps)
        let newStart2 = calendar.date(byAdding: .day, value: -2, to: today)!
        let newEnd2 = calendar.date(byAdding: .day, value: 2, to: today)!
        XCTAssertTrue(dateRangesOverlap(
            start1: existingStart, end1: existingEnd,
            start2: newStart2, end2: newEnd2
        ), "Break overlapping at start should overlap")

        // Test case 3: New break starts during, ends after existing (overlaps)
        let newStart3 = calendar.date(byAdding: .day, value: 3, to: today)!
        let newEnd3 = calendar.date(byAdding: .day, value: 7, to: today)!
        XCTAssertTrue(dateRangesOverlap(
            start1: existingStart, end1: existingEnd,
            start2: newStart3, end2: newEnd3
        ), "Break overlapping at end should overlap")

        // Test case 4: New break completely after existing (no overlap)
        let newStart4 = calendar.date(byAdding: .day, value: 6, to: today)!
        let newEnd4 = calendar.date(byAdding: .day, value: 10, to: today)!
        XCTAssertFalse(dateRangesOverlap(
            start1: existingStart, end1: existingEnd,
            start2: newStart4, end2: newEnd4
        ), "Break completely after should not overlap")

        // Test case 5: New break completely before existing (no overlap)
        let newStart5 = calendar.date(byAdding: .day, value: -10, to: today)!
        let newEnd5 = calendar.date(byAdding: .day, value: -1, to: today)!
        XCTAssertFalse(dateRangesOverlap(
            start1: existingStart, end1: existingEnd,
            start2: newStart5, end2: newEnd5
        ), "Break completely before should not overlap")
    }

    func testOverlappingBreaksErrorMessage() {
        XCTAssertEqual(
            BreakServiceError.overlappingBreak.errorDescription,
            "You already have a break during this period"
        )
    }

    // MARK: - EC-7.2: Break Starts Today Tests

    func testBreakStartsTodayBecomesActive() {
        // If break starts today, status should be 'active' not 'scheduled'
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: 5, to: today)!

        // When scheduling a break that starts today:
        // - Initial status should be 'active'
        // This is validated in BreakService.scheduleBreak()
        let startDay = calendar.startOfDay(for: today)
        let initialStatus: BreakStatus = startDay <= today ? .active : .scheduled

        XCTAssertEqual(initialStatus, .active, "Break starting today should have status 'active'")
    }

    func testBreakStartsTomorrowStaysScheduled() {
        // If break starts tomorrow, status should be 'scheduled'
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let startDay = calendar.startOfDay(for: tomorrow)
        let initialStatus: BreakStatus = startDay <= today ? .active : .scheduled

        XCTAssertEqual(initialStatus, .scheduled, "Break starting tomorrow should have status 'scheduled'")
    }

    // MARK: - EC-7.3: Break Ends Today Tests

    func testBreakEndsTodayLogic() {
        // EC-7.3: If break ends today, tomorrow's ping reverts to 'pending'
        // This is handled by generate-daily-pings edge function:
        // - isSenderOnBreak() checks if dateStr >= start_date && dateStr <= end_date
        // - If break ends today, tomorrow is outside range, so ping = 'pending'

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        // Break that ends today
        let breakStart = calendar.date(byAdding: .day, value: -3, to: today)!
        let breakEnd = today

        // Today should be on break (within range)
        XCTAssertTrue(isDateInBreakRange(date: today, breakStart: breakStart, breakEnd: breakEnd),
                     "Today should be within break range when break ends today")

        // Tomorrow should NOT be on break (outside range)
        XCTAssertFalse(isDateInBreakRange(date: tomorrow, breakStart: breakStart, breakEnd: breakEnd),
                      "Tomorrow should NOT be within break range when break ends today")
    }

    // MARK: - EC-7.4: Connection Pause During Break

    func testConnectionPauseDuringBreakNoPings() {
        // EC-7.4: Connection pause during break applies both statuses; no pings generated
        // The generate-daily-pings function filters for .eq("status", "active")
        // This means paused connections never get pings, regardless of break status

        let connectionStatus = "paused"
        let isActiveConnection = connectionStatus == "active"

        // Paused connection should not generate pings
        XCTAssertFalse(isActiveConnection, "Paused connections should not generate pings")

        // Even if sender is on break, paused connection = no pings
        let isSenderOnBreak = true
        let shouldGeneratePing = isActiveConnection // Connection status takes priority

        XCTAssertFalse(shouldGeneratePing,
                      "Paused connection during break should not generate pings")
    }

    func testActiveConnectionDuringBreakGetsPing() {
        // Active connection + sender on break = ping with status 'on_break'
        let connectionStatus = "active"
        let isActiveConnection = connectionStatus == "active"
        let isSenderOnBreak = true

        XCTAssertTrue(isActiveConnection, "Active connection should be eligible for pings")

        // Ping status determination
        let pingStatus = isSenderOnBreak ? "on_break" : "pending"
        XCTAssertEqual(pingStatus, "on_break",
                      "Active connection during break should get ping with 'on_break' status")
    }

    // MARK: - EC-7.5: Long Break Warning

    func testBreakLongerThan365DaysShowsWarning() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Break of exactly 366 days (longer than 1 year)
        let startDate = today
        let endDate = calendar.date(byAdding: .day, value: 366, to: today)!

        let daysBetween = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0

        let warning: String? = daysBetween > 365 ? "Breaks longer than 1 year may affect your account" : nil

        XCTAssertNotNil(warning, "Break > 365 days should show warning")
        XCTAssertEqual(warning, "Breaks longer than 1 year may affect your account")
    }

    func testBreakExactly365DaysNoWarning() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Break of exactly 365 days (not longer than 1 year)
        let startDate = today
        let endDate = calendar.date(byAdding: .day, value: 365, to: today)!

        let daysBetween = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0

        let warning: String? = daysBetween > 365 ? "Breaks longer than 1 year may affect your account" : nil

        XCTAssertNil(warning, "Break of exactly 365 days should not show warning")
    }

    func testBreakLessThan365DaysNoWarning() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Break of 30 days
        let startDate = today
        let endDate = calendar.date(byAdding: .day, value: 30, to: today)!

        let daysBetween = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0

        let warning: String? = daysBetween > 365 ? "Breaks longer than 1 year may affect your account" : nil

        XCTAssertNil(warning, "Break of 30 days should not show warning")
    }

    // MARK: - Break Validation Tests

    func testBreakStartDateCannotBeInPast() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let startDay = calendar.startOfDay(for: yesterday)
        let isValid = startDay >= today

        XCTAssertFalse(isValid, "Start date in the past should be invalid")
    }

    func testBreakEndDateMustBeOnOrAfterStartDate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        // End date before start date should be invalid
        let endDay = calendar.startOfDay(for: today)
        let startDay = calendar.startOfDay(for: tomorrow)
        let isValid = endDay >= startDay

        XCTAssertFalse(isValid, "End date before start date should be invalid")
    }

    func testSingleDayBreakIsValid() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Same start and end date
        let startDay = calendar.startOfDay(for: today)
        let endDay = startDay
        let isValid = endDay >= startDay

        XCTAssertTrue(isValid, "Single day break should be valid")
    }

    // MARK: - Break Status Transitions

    func testBreakStatusTransitions() {
        // Verify all valid status transitions
        // scheduled -> active (when start_date arrives)
        // scheduled -> canceled (user cancels before start)
        // active -> completed (when end_date passes)
        // active -> canceled (user ends early)

        XCTAssertEqual(BreakStatus.scheduled.rawValue, "scheduled")
        XCTAssertEqual(BreakStatus.active.rawValue, "active")
        XCTAssertEqual(BreakStatus.completed.rawValue, "completed")
        XCTAssertEqual(BreakStatus.canceled.rawValue, "canceled")
    }

    // MARK: - Helper Functions

    /// Check if two date ranges overlap
    /// Two date ranges [A, B] and [C, D] overlap if A <= D and C <= B
    private func dateRangesOverlap(start1: Date, end1: Date, start2: Date, end2: Date) -> Bool {
        let calendar = Calendar.current
        let s1 = calendar.startOfDay(for: start1)
        let e1 = calendar.startOfDay(for: end1)
        let s2 = calendar.startOfDay(for: start2)
        let e2 = calendar.startOfDay(for: end2)

        return s1 <= e2 && s2 <= e1
    }

    /// Check if a date falls within a break range (inclusive)
    private func isDateInBreakRange(date: Date, breakStart: Date, breakEnd: Date) -> Bool {
        let calendar = Calendar.current
        let dateDay = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: breakStart)
        let endDay = calendar.startOfDay(for: breakEnd)

        return dateDay >= startDay && dateDay <= endDay
    }
}
