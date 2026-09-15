/// One page of the week view's graph panel (MVP1-55/MVP1-60) — the single source of truth for
/// `GraphPanelPagerView`'s own page order (which its `body` otherwise only expresses implicitly,
/// as the order three chart views appear in its `HStack`) and for `WeekView.showGraphInfo(for:)`'s
/// own mapping from a tapped page to the metric/screen it opens. Sharing this one enum, rather than
/// each side keeping its own raw `Int`, means reordering or adding a page is a compiler error at
/// every switch over it (no `default:` catch-all to silently paper over a mismatch) instead of a
/// runtime bug where a tap opens the wrong metric's info screen.
enum GraphPanelPage: Int, CaseIterable {
    case dailyLoad = 0
    case form = 1
    case timeInZone = 2
}
