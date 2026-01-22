import XCTest
@testable import PRUUF

/// Core tests for PRUUF application
final class PRUUFTests: XCTestCase {

    // MARK: - Model Tests

    func testUserInitialsFromDisplayName() {
        // Test single word name
        let singleName = makeUser(displayName: "John")
        XCTAssertEqual(singleName.initials, "J")

        // Test two word name
        let twoWordName = makeUser(displayName: "John Doe")
        XCTAssertEqual(twoWordName.initials, "JD")

        // Test no display name
        let noName = makeUser(displayName: nil)
        XCTAssertEqual(noName.initials, "?")
    }

    func testPingStatusIsCompleted() {
        let now = Date()
        let completedPing = Ping(
            id: UUID(),
            connectionId: UUID(),
            senderId: UUID(),
            receiverId: UUID(),
            scheduledTime: now.addingTimeInterval(-3600),
            deadlineTime: now.addingTimeInterval(3600),
            completedAt: now,
            completionMethod: .tap,
            status: .completed,
            createdAt: now,
            verificationLocation: nil,
            notes: nil
        )
        XCTAssertTrue(completedPing.isCompleted)

        let pendingPing = Ping(
            id: UUID(),
            connectionId: UUID(),
            senderId: UUID(),
            receiverId: UUID(),
            scheduledTime: now.addingTimeInterval(-3600),
            deadlineTime: now.addingTimeInterval(3600),
            completedAt: nil,
            completionMethod: nil,
            status: .pending,
            createdAt: now,
            verificationLocation: nil,
            notes: nil
        )
        XCTAssertFalse(pendingPing.isCompleted)
    }

    func testPingTimeRemaining() {
        let now = Date()
        let futurePing = Ping(
            id: UUID(),
            connectionId: UUID(),
            senderId: UUID(),
            receiverId: UUID(),
            scheduledTime: now,
            deadlineTime: now.addingTimeInterval(1800), // 30 minutes from now
            completedAt: nil,
            completionMethod: nil,
            status: .pending,
            createdAt: now,
            verificationLocation: nil,
            notes: nil
        )
        XCTAssertGreaterThan(futurePing.timeRemaining, 1700) // Should be close to 1800

        let expiredPing = Ping(
            id: UUID(),
            connectionId: UUID(),
            senderId: UUID(),
            receiverId: UUID(),
            scheduledTime: now.addingTimeInterval(-7200),
            deadlineTime: now.addingTimeInterval(-3600), // 1 hour ago
            completedAt: nil,
            completionMethod: nil,
            status: .missed,
            createdAt: now,
            verificationLocation: nil,
            notes: nil
        )
        XCTAssertEqual(expiredPing.timeRemaining, 0)
    }

    func testConnectionIsActive() {
        let activeConnection = Connection(
            id: UUID(),
            senderId: UUID(),
            receiverId: UUID(),
            status: .active,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil,
            connectionCode: nil,
            receiver: nil,
            sender: nil
        )
        XCTAssertTrue(activeConnection.isActive)
        XCTAssertFalse(activeConnection.isPending)

        let pendingConnection = Connection(
            id: UUID(),
            senderId: UUID(),
            receiverId: UUID(),
            status: .pending,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil,
            connectionCode: nil,
            receiver: nil,
            sender: nil
        )
        XCTAssertFalse(pendingConnection.isActive)
        XCTAssertTrue(pendingConnection.isPending)
    }

    func testBreakIsCurrentlyActive() {
        let now = Date()

        let activeBreak = Break(
            id: UUID(),
            senderId: UUID(),
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(3600),
            createdAt: now,
            status: .active,
            notes: nil
        )
        XCTAssertTrue(activeBreak.isCurrentlyActive)

        let inactiveBreak = Break(
            id: UUID(),
            senderId: UUID(),
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(3600),
            createdAt: now,
            status: .canceled,
            notes: nil
        )
        XCTAssertFalse(inactiveBreak.isCurrentlyActive)

        let calendar = Calendar.current
        let expiredStart = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let expiredEnd = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        let expiredBreak = Break(
            id: UUID(),
            senderId: UUID(),
            startDate: expiredStart,
            endDate: expiredEnd,
            createdAt: now,
            status: .active,
            notes: nil
        )
        XCTAssertFalse(expiredBreak.isCurrentlyActive)
    }

    // MARK: - Validation Tests

    func testPhoneNumberValidation() {
        XCTAssertTrue(Validation.isValidPhoneNumber("+11234567890"))
        XCTAssertTrue(Validation.isValidPhoneNumber("+447911123456"))
        XCTAssertFalse(Validation.isValidPhoneNumber("1234567890")) // Missing +
        XCTAssertFalse(Validation.isValidPhoneNumber("+1")) // Too short
        XCTAssertFalse(Validation.isValidPhoneNumber("+0123456789")) // Starts with 0
    }

    func testVerificationCodeValidation() {
        XCTAssertTrue(Validation.isValidVerificationCode("123456"))
        XCTAssertTrue(Validation.isValidVerificationCode("000000"))
        XCTAssertFalse(Validation.isValidVerificationCode("12345")) // Too short
        XCTAssertFalse(Validation.isValidVerificationCode("1234567")) // Too long
        XCTAssertFalse(Validation.isValidVerificationCode("abcdef")) // Not digits
    }

    func testDisplayNameValidation() {
        XCTAssertTrue(Validation.isValidDisplayName("Jo"))
        XCTAssertTrue(Validation.isValidDisplayName("John Doe"))
        XCTAssertFalse(Validation.isValidDisplayName("J")) // Too short
        XCTAssertFalse(Validation.isValidDisplayName("   ")) // Only whitespace
        XCTAssertFalse(Validation.isValidDisplayName(String(repeating: "a", count: 51))) // Too long
    }

    // MARK: - Extension Tests

    func testStringInitials() {
        XCTAssertEqual("John".initials, "J")
        XCTAssertEqual("John Doe".initials, "JD")
        XCTAssertEqual("John Middle Doe".initials, "JM")
        XCTAssertEqual("".initials, "")
    }

    func testStringTrimmed() {
        XCTAssertEqual("  hello  ".trimmed, "hello")
        XCTAssertEqual("\n\thello\n\t".trimmed, "hello")
        XCTAssertEqual("hello".trimmed, "hello")
    }

    func testOptionalStringOrEmpty() {
        let someString: String? = "hello"
        let nilString: String? = nil

        XCTAssertEqual(someString.orEmpty, "hello")
        XCTAssertEqual(nilString.orEmpty, "")
    }

    func testArraySafeSubscript() {
        let array = [1, 2, 3]

        XCTAssertEqual(array[safe: 0], 1)
        XCTAssertEqual(array[safe: 2], 3)
        XCTAssertNil(array[safe: 3])
        XCTAssertNil(array[safe: -1])
    }

    // MARK: - Helpers

    private func makeUser(displayName: String?) -> PruufUser {
        PruufUser(
            id: UUID(),
            phoneNumber: "1234567890",
            phoneCountryCode: "+1",
            createdAt: Date(),
            updatedAt: Date(),
            lastSeenAt: nil,
            isActive: true,
            hasCompletedOnboarding: true,
            primaryRole: .sender,
            timezone: "UTC",
            deviceToken: nil,
            notificationPreferences: .defaults,
            onboardingStep: nil,
            displayName: displayName,
            avatarURL: nil
        )
    }
}
