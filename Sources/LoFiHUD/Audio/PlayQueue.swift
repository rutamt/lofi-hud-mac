import Foundation

/// Shuffled play order with history. Pure value type (no audio), so it's unit-testable.
///
/// - The order is reshuffled each time it wraps around, with the current song moved to the
///   end so the same track never plays twice in a row.
/// - "Previous" walks a history of actually played songs, so it survives reshuffles.
/// - Rescans merge new files into the upcoming part of the order without disturbing playback.
struct PlayQueue {
    private(set) var order: [URL] = []
    /// Position of the current song in `order`; -1 means "before the first song".
    /// When `onSong` is false, `index` is just the slot *before* the next song
    /// (the playing song was removed or filtered out).
    private(set) var index = -1
    private var onSong = false
    private var history: [URL] = []
    private var preparedWrap = false
    private static let historyLimit = 200

    var count: Int { order.count }
    var isEmpty: Bool { order.isEmpty }
    var current: URL? { onSong && order.indices.contains(index) ? order[index] : nil }
    var startIndex: Int { order.indices.contains(index) ? index : 0 }

    init() {}

    /// Initial load. Keeps `savedOrder` for files that still exist, shuffles in new ones.
    init(files: [URL], savedOrder: [URL] = [], current: URL? = nil) {
        let present = Set(files)
        var o = savedOrder.filter(present.contains)
        let known = Set(o)
        o.append(contentsOf: files.filter { !known.contains($0) }.shuffled())
        if savedOrder.isEmpty { o.shuffle() }
        order = o
        if let i = current.flatMap(o.firstIndex(of:)) {
            index = i
            onSong = true
        }
    }

    /// Index of the song that plays after the current one. Reshuffles once on wrap-around.
    mutating func nextIndex() -> Int? {
        guard !order.isEmpty else { return nil }
        if index >= order.count - 1, !preparedWrap {
            reshuffleKeepingCurrentLast()
            preparedWrap = true
        }
        return (index + 1) % order.count
    }

    /// Index to go back to: the last played song still in the queue, else the previous slot.
    mutating func previousIndex() -> Int? {
        guard !order.isEmpty else { return nil }
        while let url = history.popLast() {
            if url != current, let i = order.firstIndex(of: url) { return i }
        }
        return (max(index, 0) - 1 + order.count) % order.count
    }

    /// Make `i` the current song. `remember` records the outgoing song for "Previous".
    mutating func select(_ i: Int, remember: Bool) {
        guard order.indices.contains(i) else { return }
        if remember, let cur = current, cur != order[i] {
            history.append(cur)
            if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        }
        index = i
        onSong = true
        preparedWrap = false
    }

    mutating func select(_ url: URL, remember: Bool) {
        if let i = order.firstIndex(of: url) { select(i, remember: remember) }
    }

    /// Remove a song. If it was current, `nextIndex()` then yields the song that slid into its slot.
    mutating func remove(_ url: URL) {
        guard let i = order.firstIndex(of: url) else { return }
        order.remove(at: i)
        if i == index { onSong = false }
        if i <= index { index -= 1 }
        preparedWrap = false
    }

    /// Put `url` back right after the current position and make it current (used by Undo).
    mutating func insertAsCurrent(_ url: URL) {
        if let i = order.firstIndex(of: url) {
            select(i, remember: true)
            return
        }
        let at = min(index + 1, order.count)
        order.insert(url, at: at)
        select(at, remember: true)
    }

    /// Replace the song set (rescan or filter change) while keeping the order of known songs.
    /// New songs are spread randomly through the upcoming part of this cycle.
    /// `playing` stays the anchor even if it is no longer part of the set.
    mutating func merge(_ files: [URL], playing: URL?) {
        let present = Set(files)
        let known = Set(order)
        let anchorURL = playing ?? current

        // Count how many kept songs came before the anchor, to find the "upcoming" boundary.
        var kept: [URL] = []
        var keptBeforeAnchor = 0
        let anchorPos = anchorURL.flatMap(order.firstIndex(of:)) ?? index
        for (i, url) in order.enumerated() where present.contains(url) {
            kept.append(url)
            if i <= anchorPos { keptBeforeAnchor += 1 }
        }

        for url in files where !known.contains(url) {
            kept.insert(url, at: Int.random(in: keptBeforeAnchor...kept.count))
        }
        order = kept
        if let anchorURL, let i = order.firstIndex(of: anchorURL) {
            index = i
            onSong = true
        } else {
            index = keptBeforeAnchor - 1
            onSong = false
        }
        preparedWrap = false
    }

    private mutating func reshuffleKeepingCurrentLast() {
        let cur = current
        var o = order.shuffled()
        if let cur, let i = o.firstIndex(of: cur) {
            o.remove(at: i)
            o.append(cur)
            index = o.count - 1
        } else {
            index = -1
            onSong = false
        }
        order = o
    }
}
