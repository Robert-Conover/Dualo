import Foundation
import Testing
@testable import Dualo

struct ConversationPinningTests {
    @Test func savedChatsWithoutAPinFieldStillLoad() throws {
        let conversation = Conversation(title: "Existing chat", provider: .local, model: "qwen3.5-0.8b-q4")
        let encoded = try JSONEncoder().encode(conversation)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "isPinned")

        let data = try JSONSerialization.data(withJSONObject: json)
        let loaded = try JSONDecoder().decode(Conversation.self, from: data)

        #expect(!loaded.isPinned)
        #expect(loaded == conversation)
    }

    @Test(arguments: [false, true])
    func pinStateSurvivesSavingAndLoading(_ isPinned: Bool) throws {
        var conversation = Conversation(title: "Saved chat", provider: .openai, model: "gpt-6.1-sol")
        conversation.isPinned = isPinned
        conversation.addMessage(Message(role: Message.Role.user, content: "Keep this conversation"))

        let data = try JSONEncoder().encode(conversation)
        let loaded = try JSONDecoder().decode(Conversation.self, from: data)

        #expect(loaded == conversation)
    }
}
