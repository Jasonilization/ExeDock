import Foundation

extension Array {
    /// Bounds-checked indexing - `nil` for an out-of-range index instead of a crash. Used
    /// throughout the controller-navigation code, where a focus index/id can go stale the moment
    /// the underlying list changes size (a game removed, a folder collapsed, Advanced Mode
    /// toggled off) - reading defensively here means that degrades to "nothing focused" instead of
    /// a trap.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    /// Splits into fixed-size groups (the last one shorter if it doesn't divide evenly) - used to
    /// lay out photo thumbnails in explicit rows rather than an adaptive grid, so every row has a
    /// predictable, fixed number of items regardless of the container's exact measured width.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
