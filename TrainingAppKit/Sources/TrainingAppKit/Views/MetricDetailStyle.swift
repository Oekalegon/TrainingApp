import SwiftUI

/// Shared background colors for `MetricDetailView`'s Apple Health-style layout (MVP1-45) — plain
/// white above the chart, grouped below it (see `MetricDetailView`'s own doc comment) — and for
/// `HeartRateZoneDetailView` (MVP1-60), which reuses the same visual language rather than
/// inventing its own.
#if os(iOS)
let metricDetailBackground = Color(.systemGroupedBackground)
let metricDetailChartCardBackground = Color(.systemBackground)
let metricDetailAboutCardBackground = Color(.secondarySystemGroupedBackground)
#else
// These views only ever ship on iOS; the fallback exists purely so TrainingAppKit (built for both
// iOS and macOS, per Package.swift) still compiles on macOS, e.g. for host-side tooling/tests.
let metricDetailBackground = Color(white: 0.93)
let metricDetailChartCardBackground = Color.white
let metricDetailAboutCardBackground = Color(white: 0.97)
#endif
