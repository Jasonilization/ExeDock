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
}
