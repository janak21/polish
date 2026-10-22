import Testing
@testable import Polish

@Test func costUsesHaikuPrices() {
    #expect(Stats.Entry(requests: 1, inputTokens: 1_000_000, outputTokens: 1_000_000).cost == 0.60)
    #expect(Stats.Entry(requests: 1, inputTokens: 200, outputTokens: 100).cost == 0.00007)
}
