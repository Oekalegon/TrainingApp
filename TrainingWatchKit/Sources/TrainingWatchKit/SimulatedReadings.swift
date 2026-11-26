import Foundation

/// Made-up readings for the simulator, which measures none of ``RunQuantity``'s sensors (WATCH-135): slow waves
/// around a plausible easy run, so the run screens' cadence, form and power metrics can be seen to move. Not
/// meant to look like a run, and never used on a watch.
public enum SimulatedReadings {
    /// The readings of the quantities other than heart rate, `elapsed` seconds into the run.
    public static func values(atElapsed elapsed: TimeInterval) -> [RunQuantity: Double] {
        func wave(_ center: Double, _ amplitude: Double, period: Double) -> Double {
            center + amplitude * sin(elapsed / period * 2 * .pi)
        }
        return [
            .cadence: wave(168, 8, period: 90),
            .runningSpeed: wave(2.9, 0.4, period: 120),
            .strideLength: wave(1.05, 0.08, period: 120),
            .groundContactTime: wave(245, 20, period: 75),
            .verticalOscillation: wave(8.5, 0.8, period: 60),
            .runningPower: wave(230, 25, period: 100),
        ]
    }
}
