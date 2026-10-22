import Testing
@testable import Polish

private func rebuild(_ parts: [Diff.Part], keepRemoved: Bool) -> String {
    parts.map {
        switch $0 {
        case .same(let s): s
        case .removed(let s): keepRemoved ? s : ""
        case .added(let s): keepRemoved ? "" : s
        }
    }.joined()
}

@Test func diffRoundTripsBothTexts() {
    let old = "I has a informations about the meeting, 🙂 @sam.\nThanks"
    let new = "I have some information about the meeting, 🙂 @sam.\nThanks!"
    let parts = Diff.parts(from: old, to: new)
    #expect(rebuild(parts, keepRemoved: true) == old)
    #expect(rebuild(parts, keepRemoved: false) == new)
    #expect(parts.contains(.removed("has")))
    #expect(parts.contains(.added("have")))
}

@Test func identicalTextIsOneUnchangedPart() {
    #expect(Diff.parts(from: "Looks good.", to: "Looks good.") == [.same("Looks good.")])
}

@Test func emptyInputs() {
    #expect(Diff.parts(from: "", to: "Hi") == [.added("Hi")])
    #expect(Diff.parts(from: "Hi", to: "") == [.removed("Hi")])
}
