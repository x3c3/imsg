import Commander
import Foundation
import IMsgCore

enum PollCommand {
  static let spec = CommandSpec(
    name: "poll",
    abstract: "Send a native Apple Messages poll",
    discussion: """
      Requires `imsg launch` (SIP-disabled, dylib injected). Use the `send`
      action to create a native Messages Polls extension balloon.
      """,
    signature: CommandSignatures.withRuntimeFlags(
      CommandSignature(
        arguments: [
          .make(label: "action", help: "send", isOptional: false)
        ],
        options: CommandSignatures.baseOptions() + [
          .make(label: "chat", names: [.long("chat")], help: "chat guid or rowid"),
          .make(label: "chatID", names: [.long("chat-id")], help: "chat rowid"),
          .make(label: "question", names: [.long("question")], help: "poll question"),
          .make(label: "replyTo", names: [.long("reply-to")], help: "guid of message to reply to"),
          .make(
            label: "option", names: [.long("option")],
            help: "poll option text; pass at least twice"),
        ]
      )
    ),
    usageExamples: [
      "imsg poll send --chat 'iMessage;-;+15551234567' --question 'Dinner?' --option 'Pizza' --option 'Sushi'",
      "imsg poll send --chat 'iMessage;-;+15551234567' --reply-to ABCD --question 'Approve?' --option 'Yes' --option 'No'",
    ]
  ) { values, runtime in
    try await run(values: values, runtime: runtime)
  }

  static func run(
    values: ParsedValues,
    runtime: RuntimeOptions,
    storeFactory: @escaping (String) throws -> MessageStore = { try MessageStore(path: $0) },
    invokeBridge: @escaping (BridgeAction, [String: Any]) async throws -> [String: Any] = {
      action, params in
      try await IMsgBridgeClient.shared.invoke(action: action, params: params)
    }
  ) async throws {
    guard values.argument(0) == "send" else {
      throw ParsedValuesError.invalidOption("action")
    }
    let chat = try resolveChatGUID(values: values, storeFactory: storeFactory)
    guard let question = values.option("question"), !question.isEmpty else {
      throw ParsedValuesError.missingOption("question")
    }
    let options = values.optionValues("option")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard options.count >= 2 else {
      throw ParsedValuesError.missingOption("option")
    }

    var params: [String: Any] = [
      "chatGuid": chat,
      "question": question,
      "options": options,
    ]
    if let reply = values.option("replyTo"), !reply.isEmpty {
      params["selectedMessageGuid"] = reply
    }

    _ = try await BridgeOutput.invokeAndEmit(
      action: .sendPoll,
      params: params,
      runtime: runtime,
      invokeBridge: invokeBridge
    ) { data in
      let guid = (data["messageGuid"] as? String) ?? ""
      return guid.isEmpty ? "poll: queued" : "poll: sent (guid=\(guid))"
    }
  }

  private static func resolveChatGUID(
    values: ParsedValues,
    storeFactory: (String) throws -> MessageStore
  ) throws -> String {
    let chatValue = values.option("chat")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let chatID = values.optionInt64("chatID") ?? Int64(chatValue)
    if let chatID {
      let dbPath = values.option("db") ?? MessageStore.defaultPath
      let store = try storeFactory(dbPath)
      guard let info = try store.chatInfo(chatID: chatID) else {
        throw IMsgError.chatNotFound(chatID: chatID)
      }
      return info.guid.isEmpty ? info.identifier : info.guid
    }
    guard !chatValue.isEmpty else {
      throw ParsedValuesError.missingOption("chat")
    }
    return chatValue
  }
}
