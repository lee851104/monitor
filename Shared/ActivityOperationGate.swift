/// Cancels publication after an identity change and excludes overlapping starts.
struct ActivityOperationGate {
    private(set) var generation = 0
    private(set) var isBusy = false

    mutating func begin() -> Int? {
        guard !isBusy else { return nil }
        generation += 1
        isBusy = true
        return generation
    }

    func accepts(_ ticket: Int) -> Bool { ticket == generation }

    mutating func finish(_ ticket: Int) {
        if accepts(ticket) { isBusy = false }
    }

    mutating func invalidate() {
        generation += 1
        isBusy = false
    }
}
