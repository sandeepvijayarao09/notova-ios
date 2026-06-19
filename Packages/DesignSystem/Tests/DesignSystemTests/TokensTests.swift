import XCTest
import SwiftUI
@testable import DesignSystem

/// Smoke tests for the pure token values. These guard against accidental
/// changes to the spacing scale and ensure the color/typography tokens are
/// constructible (a compile + access check that catches removed members).
final class TokensTests: XCTestCase {

    // MARK: - Spacing scale

    func testSpacingScaleValues() {
        XCTAssertEqual(NotovaSpacing.xs, 4)
        XCTAssertEqual(NotovaSpacing.sm, 8)
        XCTAssertEqual(NotovaSpacing.md, 16)
        XCTAssertEqual(NotovaSpacing.lg, 24)
        XCTAssertEqual(NotovaSpacing.xl, 32)
    }

    func testSpacingScaleIsMonotonicallyIncreasing() {
        let scale = [NotovaSpacing.xs, NotovaSpacing.sm, NotovaSpacing.md, NotovaSpacing.lg, NotovaSpacing.xl]
        XCTAssertEqual(scale, scale.sorted())
        XCTAssertEqual(Set(scale).count, scale.count, "spacing steps should be distinct")
    }

    func testSpacingAllPositive() {
        for value in [NotovaSpacing.xs, NotovaSpacing.sm, NotovaSpacing.md, NotovaSpacing.lg, NotovaSpacing.xl] {
            XCTAssertGreaterThan(value, 0)
        }
    }

    // MARK: - Colors

    func testColorTokensAreDistinctAccentAndRecording() {
        // Accent (indigo-ish) and recording (red-ish) must differ so the record
        // button visibly changes state.
        XCTAssertNotEqual(NotovaColor.accent, NotovaColor.recording)
    }

    func testColorTokensAreAccessible() {
        // Pure access check — ensures the static members still exist.
        _ = NotovaColor.accent
        _ = NotovaColor.recording
        _ = NotovaColor.surface
        _ = NotovaColor.textPrimary
        _ = NotovaColor.textSecondary
        XCTAssertEqual(NotovaColor.textPrimary, Color.primary)
        XCTAssertEqual(NotovaColor.textSecondary, Color.secondary)
    }

    // MARK: - Typography

    func testFontTokensAreAccessible() {
        _ = NotovaFont.title
        _ = NotovaFont.heading
        _ = NotovaFont.body
        _ = NotovaFont.caption
        XCTAssertEqual(NotovaFont.body, Font.system(.body))
    }
}
