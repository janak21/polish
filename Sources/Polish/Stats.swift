import Foundation
import Observation

/// Request and token counts per model, kept across launches, for the Stats menu.
@MainActor @Observable
final class Stats {
    struct Entry: Codable {
        var requests = 0
        var inputTokens = 0
        var outputTokens = 0

        /// Estimated USD at claude-haiku-5-5 list prices: $0.10 input / $0.50 output per million tokens.
        var cost: Double { (Double(inputTokens) * 0.10 + Double(outputTokens) * 0.50) / 1_000_000 }
    }

    struct Totals: Codable {
        var claude = Entry()
        var onDevice = Entry()
        var since = Date.now
    }

    static let shared = Stats()

    private(set) var totals: Totals {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(totals), forKey: "stats") }
    }

    private init() {
        let data = UserDefaults.standard.data(forKey: "stats")
        totals = data.flatMap { try? JSONDecoder().decode(Totals.self, from: $0) } ?? Totals()
    }

    func recordClaude(inputTokens: Int, outputTokens: Int) {
        totals.claude.requests += 1
        totals.claude.inputTokens += inputTokens
        totals.claude.outputTokens += outputTokens
    }

    func recordOnDevice() { totals.onDevice.requests += 1 }

    func reset() { totals = Totals() }
}
