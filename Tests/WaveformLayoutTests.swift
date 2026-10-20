import Foundation

enum WaveformLayoutTests {
    static func run() {
        testPresets()
        testDictationGeometry()
        testMeetingGeometry()
        testOddAndDegenerateCounts()
        testScaleNeverDropsBelowMinimum()
        testBarHeight()
        testShimmerSweep()
    }

    private static func testPresets() {
        TestSupport.expectEqual(WaveformLayout.dictation, WaveformLayout(barCount: 10, bulge: 12))
        TestSupport.expectEqual(WaveformLayout.meeting, WaveformLayout(barCount: 5, bulge: 18))
        TestSupport.expectEqual(WaveformLayout.minimumScale, 0.25)
        TestSupport.expectEqual(WaveformLayout.rippleDelayPerStep, 0.1)
    }

    private static func testDictationGeometry() {
        let layout = WaveformLayout.dictation
        let bars = 0..<layout.barCount
        TestSupport.expectEqual(bars.map(layout.steps(fromCenter:)), [4, 3, 2, 1, 0, 0, 1, 2, 3, 4])
        expectValues(bars.map(layout.normalizedDistance(ofBar:)), [1, 0.75, 0.5, 0.25, 0, 0, 0.25, 0.5, 0.75, 1])
        expectValues(
            bars.map(layout.scale(ofBar:)),
            [0.75, 0.859375, 0.9375, 0.984375, 1, 1, 0.984375, 0.9375, 0.859375, 0.75]
        )
        expectValues(bars.map(layout.rippleDelay(ofBar:)), [0.4, 0.3, 0.2, 0.1, 0, 0, 0.1, 0.2, 0.3, 0.4])
    }

    private static func testMeetingGeometry() {
        let layout = WaveformLayout.meeting
        let bars = 0..<layout.barCount
        TestSupport.expectEqual(bars.map(layout.steps(fromCenter:)), [2, 1, 0, 1, 2])
        expectValues(bars.map(layout.normalizedDistance(ofBar:)), [1, 0.5, 0, 0.5, 1])
        expectValues(bars.map(layout.scale(ofBar:)), [0.625, 0.90625, 1, 0.90625, 0.625])
        expectValues(bars.map(layout.rippleDelay(ofBar:)), [0.2, 0.1, 0, 0.1, 0.2])
    }

    private static func testOddAndDegenerateCounts() {
        let three = WaveformLayout(barCount: 3, bulge: 24)
        TestSupport.expectEqual((0..<3).map(three.steps(fromCenter:)), [1, 0, 1])
        expectValues((0..<3).map(three.scale(ofBar:)), [0.5, 1, 0.5])

        let single = WaveformLayout(barCount: 1, bulge: 18)
        TestSupport.expectEqual(single.steps(fromCenter: 0), 0)
        TestSupport.expectEqual(single.normalizedDistance(ofBar: 0), 0)
        TestSupport.expectEqual(single.scale(ofBar: 0), 1)
    }

    private static func testScaleNeverDropsBelowMinimum() {
        let steep = WaveformLayout(barCount: 5, bulge: 96)
        expectValues((0..<5).map(steep.scale(ofBar:)), [0.25, 0.5, 1, 0.5, 0.25])
    }

    private static func testBarHeight() {
        let layout = WaveformLayout.dictation
        func height(_ index: Int, _ level: Double) -> Double {
            Double(layout.barHeight(ofBar: index, level: level, minHeight: 2, maxHeight: 22))
        }
        TestSupport.expectApproximatelyEqual(height(4, 0), 2)
        TestSupport.expectApproximatelyEqual(height(4, 1), 22)
        TestSupport.expectApproximatelyEqual(height(0, 1), 17)
        TestSupport.expectApproximatelyEqual(height(0, 0.5), 9.5)
        TestSupport.expectApproximatelyEqual(height(6, 0.5), 2 + 20 * 0.5 * 0.984375)
        TestSupport.expectApproximatelyEqual(height(5, 1.7), 22)
        TestSupport.expectApproximatelyEqual(height(9, 3), 17)
        TestSupport.expectApproximatelyEqual(height(5, -0.3), 2)
        TestSupport.expectApproximatelyEqual(
            Double(WaveformLayout.meeting.barHeight(ofBar: 0, level: 0.8, minHeight: 4, maxHeight: 12)),
            4 + 8 * 0.8 * 0.625
        )
    }

    private static func testShimmerSweep() {
        let layout = WaveformLayout.dictation
        let period = WaveformLayout.shimmerPeriod
        TestSupport.expectEqual(period, 1.2)
        TestSupport.expectEqual(WaveformLayout.shimmerBandWidth, 2)
        // The highlight head travels from -2 to 11 (13 bar widths) per period.
        func time(headAt head: Double, cycle: Double = 0) -> Double {
            (cycle + (head + 2) / 13) * period
        }
        func brightness(at time: Double) -> [Double] {
            (0..<layout.barCount).map { layout.shimmer(ofBar: $0, time: time) }
        }

        expectValues(brightness(at: 0), Array(repeating: 0, count: 10))
        expectValues(brightness(at: time(headAt: 10.999_999)), Array(repeating: 0, count: 10), accuracy: 0.000_01)
        expectValues(brightness(at: time(headAt: 4)), [0, 0, 0, 0.5, 1, 0.5, 0, 0, 0, 0])
        expectValues(brightness(at: time(headAt: 5)), [0, 0, 0, 0, 0.5, 1, 0.5, 0, 0, 0])
        expectValues(brightness(at: time(headAt: 0.5)), [0.75, 0.75, 0.25, 0, 0, 0, 0, 0, 0, 0])
        expectValues(brightness(at: time(headAt: 4, cycle: 3)), [0, 0, 0, 0.5, 1, 0.5, 0, 0, 0, 0])
        expectValues(brightness(at: time(headAt: 4, cycle: -2)), [0, 0, 0, 0.5, 1, 0.5, 0, 0, 0, 0])
    }

    private static func expectValues(
        _ actual: [Double],
        _ expected: [Double],
        accuracy: Double = 0.000_000_1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        TestSupport.expectEqual(actual.count, expected.count, file: file, line: line)
        for (value, target) in zip(actual, expected) {
            TestSupport.expectApproximatelyEqual(value, target, accuracy: accuracy, file: file, line: line)
        }
    }
}
