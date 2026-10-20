import CoreGraphics
import Foundation

/// Bar geometry for the recording waveform. Bars mirror around the center,
/// shrink toward the edges in a lens shape, and react later the farther they
/// sit from the middle so level changes ripple outward.
struct WaveformLayout: Equatable {
    let barCount: Int
    let bulge: Double

    /// Ten bars with a gentle lens: edge bars keep 75% of the center height,
    /// enough to read as an eye shape without starving quiet speech at the edges.
    static let dictation = WaveformLayout(barCount: 10, bulge: 12)
    /// Fewer bars with a pronounced lens (edges at 62.5%) for the meeting recorder.
    static let meeting = WaveformLayout(barCount: 5, bulge: 18)

    static let minimumScale = 0.25
    static let rippleDelayPerStep = 0.1
    static let shimmerPeriod = 1.2
    static let shimmerBandWidth = 2.0

    /// Whole bar steps between bar `index` and the center; both middle bars
    /// of an even count sit at step 0.
    func steps(fromCenter index: Int) -> Int {
        (barCount - 1) / 2 - min(index, barCount - 1 - index)
    }

    /// `steps(fromCenter:)` normalized to the half-width, so the outermost bars sit at 1.
    func normalizedDistance(ofBar index: Int) -> Double {
        let maxSteps = (barCount - 1) / 2
        guard maxSteps > 0 else { return 0 }
        return Double(steps(fromCenter: index)) / Double(maxSteps)
    }

    func scale(ofBar index: Int) -> Double {
        let distance = normalizedDistance(ofBar: index)
        return max(Self.minimumScale, 1 - distance * distance * bulge / 48)
    }

    func rippleDelay(ofBar index: Int) -> Double {
        Double(steps(fromCenter: index)) * Self.rippleDelayPerStep
    }

    func barHeight(ofBar index: Int, level: Double, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let amplitude = min(max(level, 0), 1) * scale(ofBar: index)
        return minHeight + (maxHeight - minHeight) * CGFloat(amplitude)
    }

    /// Brightness (0...1) of bar `index` under a soft highlight that sweeps
    /// left to right once per `shimmerPeriod`, entering and leaving fully off-bar.
    func shimmer(ofBar index: Int, time: TimeInterval) -> Double {
        let cycles = time / Self.shimmerPeriod
        let progress = cycles - cycles.rounded(.down)
        let band = Self.shimmerBandWidth
        let head = progress * (Double(barCount - 1) + 2 * band) - band
        return max(0, 1 - abs(Double(index) - head) / band)
    }
}
