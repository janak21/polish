import Foundation
import Observation

struct Action: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var instruction: String

    static let builtIn: [Action] = [
        Action(name: "Proofread", instruction: "Fix grammar, spelling, and punctuation, and rephrase anything a native English speaker would find unnatural. Keep the tone and meaning."),
        Action(name: "Improve", instruction: "Make it clearer and more natural. Keep the meaning, length, and tone."),
        Action(name: "Rewrite", instruction: "Rewrite it in fresh wording. You may restructure it freely, but keep the meaning."),
        Action(name: "Casual", instruction: "Make the tone casual and friendly, like a message to a coworker."),
        Action(name: "Formal", instruction: "Make the tone formal and professional."),
    ]
}

@MainActor @Observable
final class CustomActions {
    static let shared = CustomActions()

    var items: [Action] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: "customActions") }
    }

    var usable: [Action] { items.filter { !$0.name.isEmpty && !$0.instruction.isEmpty } }

    private init() {
        let data = UserDefaults.standard.data(forKey: "customActions")
        items = data.flatMap { try? JSONDecoder().decode([Action].self, from: $0) } ?? []
    }
}
