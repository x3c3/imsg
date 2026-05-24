import Foundation
import SQLite
import Testing

@testable import IMsgCore

private let testPollBundleID =
  "com.apple.messages.MSMessageExtensionBalloonPlugin:0000000000:com.apple.messages.Polls"

@Test
func decodesPollCreationPayloadFromArchivedURL() throws {
  let definition: [String: Any] = [
    "title": "Dinner plan?",
    "creatorHandle": "+15550001000",
    "orderedPollOptions": [
      ["optionIdentifier": "choice-a", "pollOptionText": "Pizza"],
      ["optionIdentifier": "choice-b", "pollOptionText": "Sushi"],
    ],
  ]
  let url = try pollURL(queryName: "definition", object: definition)
  let payload = try NSKeyedArchiver.archivedData(
    withRootObject: ["url": url],
    requiringSecureCoding: false
  )

  let poll = MessagePollDecoder.decode(
    balloonBundleID: testPollBundleID,
    payloadData: payload,
    messageSummaryInfo: Data(),
    associatedMessageType: nil,
    associatedMessageGUID: "",
    messageGUID: "poll-message-guid",
    sender: "+15550001000"
  )

  #expect(poll?.kind == .created)
  #expect(poll?.event == "imessage.poll.created")
  #expect(poll?.pollGUID == "poll-message-guid")
  #expect(poll?.question == "Dinner plan?")
  #expect(poll?.creator == "+15550001000")
  #expect(
    poll?.options == [
      MessagePollOption(id: "choice-a", text: "Pizza"),
      MessagePollOption(id: "choice-b", text: "Sushi"),
    ])
  #expect(poll?.metadata?.queryKeys == ["definition", "source"])
}

@Test
func decodesPollCreationPayloadFromAppleDataURLEnvelope() throws {
  let definition: [String: Any] = [
    "item": [
      "title": "Dinner plan?",
      "creatorHandle": "+15550001000",
      "orderedPollOptions": [
        [
          "creatorHandle": "+15550001000",
          "canBeEdited": false,
          "attributedText": "Pizza",
          "text": "Pizza",
          "optionIdentifier": "choice-a",
        ],
        [
          "creatorHandle": "+15550001000",
          "canBeEdited": false,
          "attributedText": "Sushi",
          "text": "Sushi",
          "optionIdentifier": "choice-b",
        ],
      ],
    ],
    "version": 1,
  ]
  let payload = try applePollEnvelopePayload(jsonObject: definition, query: "src=p&c=2")

  let poll = MessagePollDecoder.decode(
    balloonBundleID: testPollBundleID,
    payloadData: payload,
    messageSummaryInfo: Data(),
    associatedMessageType: nil,
    associatedMessageGUID: "",
    messageGUID: "poll-message-guid",
    sender: "+15550001000"
  )

  #expect(poll?.kind == .created)
  #expect(poll?.event == "imessage.poll.created")
  #expect(poll?.question == "Dinner plan?")
  #expect(poll?.creator == "+15550001000")
  #expect(
    poll?.options == [
      MessagePollOption(id: "choice-a", text: "Pizza"),
      MessagePollOption(id: "choice-b", text: "Sushi"),
    ])
  #expect(poll?.metadata?.queryKeys == ["c", "src"])
}

@Test
func decodesPollVotePayloadFromBinaryPlistURL() throws {
  let response: [String: Any] = [
    "votes": [
      [
        "voteOptionIdentifier": "choice-b",
        "participantHandle": "+15550002000",
        "eventType": "selected",
        "serverVoteTime": 123_456,
      ]
    ]
  ]
  let url = try pollURL(queryName: "response", object: response)
  let payload = try PropertyListSerialization.data(
    fromPropertyList: ["messageURL": url.absoluteString],
    format: .binary,
    options: 0
  )

  let poll = MessagePollDecoder.decode(
    balloonBundleID: testPollBundleID,
    payloadData: payload,
    messageSummaryInfo: Data(),
    associatedMessageType: 4000,
    associatedMessageGUID: "original-poll-guid",
    messageGUID: "vote-row-guid",
    sender: "+15550002000"
  )

  #expect(poll?.kind == .vote)
  #expect(poll?.event == "imessage.poll.voted")
  #expect(poll?.pollGUID == "original-poll-guid")
  #expect(poll?.originalGUID == "original-poll-guid")
  #expect(
    poll?.vote
      == MessagePollVote(
        optionID: "choice-b",
        participant: "+15550002000",
        eventType: "selected",
        serverTime: "123456"
      ))
  #expect(poll?.participants == ["+15550002000"])
}

@Test
func decodesPollVotePayloadFromAppleDataURLEnvelope() throws {
  let response: [String: Any] = [
    "item": [
      "votes": [
        [
          "voteOptionIdentifier": "choice-b",
          "participantHandle": "+15550002000",
        ]
      ]
    ],
    "version": 1,
  ]
  let payload = try applePollEnvelopePayload(jsonObject: response)

  let poll = MessagePollDecoder.decode(
    balloonBundleID: testPollBundleID,
    payloadData: payload,
    messageSummaryInfo: Data(),
    associatedMessageType: 4000,
    associatedMessageGUID: "original-poll-guid",
    messageGUID: "vote-row-guid",
    sender: "+15550002000"
  )

  #expect(poll?.kind == .vote)
  #expect(poll?.event == "imessage.poll.voted")
  #expect(poll?.pollGUID == "original-poll-guid")
  #expect(
    poll?.vote
      == MessagePollVote(
        optionID: "choice-b",
        participant: "+15550002000",
        eventType: "selected"
      ))
}

@Test
func malformedPollPayloadEmitsUnknownWithoutRawPayload() throws {
  let poll = MessagePollDecoder.decode(
    balloonBundleID: testPollBundleID,
    payloadData: Data([0x00, 0x01, 0x02]),
    messageSummaryInfo: Data(),
    associatedMessageType: nil,
    associatedMessageGUID: "",
    messageGUID: "unknown-poll-guid",
    sender: "+15550001000"
  )

  #expect(poll?.kind == .unknown)
  #expect(poll?.event == "imessage.poll.unknown")
  #expect(poll?.metadata?.payloadBytes == 3)
  let encoded = try JSONEncoder().encode(poll)
  let json = String(decoding: encoded, as: UTF8.self)
  #expect(!json.contains("AAEC"))
}

@Test
func nonPollMessagesAreUnaffected() throws {
  let payload = try PropertyListSerialization.data(
    fromPropertyList: ["title": "Not a poll"],
    format: .binary,
    options: 0
  )

  let poll = MessagePollDecoder.decode(
    balloonBundleID: "com.apple.messages.URLBalloonProvider",
    payloadData: payload,
    messageSummaryInfo: Data(),
    associatedMessageType: nil,
    associatedMessageGUID: "",
    messageGUID: "normal-message-guid",
    sender: "+15550001000"
  )

  #expect(poll == nil)
}

@Test
func nonPollAssociatedTypeRowsAreUnaffectedWithoutPollEvidence() throws {
  let payload = try PropertyListSerialization.data(
    fromPropertyList: ["title": "Not a poll"],
    format: .binary,
    options: 0
  )

  let poll = MessagePollDecoder.decode(
    balloonBundleID: "",
    payloadData: payload,
    messageSummaryInfo: Data(),
    associatedMessageType: 4000,
    associatedMessageGUID: "associated-message-guid",
    messageGUID: "normal-message-guid",
    sender: "+15550001000"
  )

  #expect(poll == nil)
}

@Test
func messageStoreAttachesDecodedPollMetadata() throws {
  let db = try Connection(.inMemory)
  var options = MessageDatabaseFixture.SchemaOptions()
  options.includeReactionColumns = true
  options.includeBalloonBundleID = true
  options.includePayloadData = true
  options.includeMessageSummaryInfo = true
  try MessageDatabaseFixture.createSchema(db, options: options)

  try db.run(
    """
    INSERT INTO chat(ROWID, chat_identifier, guid, display_name, service_name)
    VALUES (1, '+15550001000', 'iMessage;+;chat-test', 'Poll Test', 'iMessage')
    """
  )
  try db.run("INSERT INTO handle(ROWID, id) VALUES (1, '+15550001000')")

  let definition: [String: Any] = [
    "title": "Pick one",
    "orderedPollOptions": [
      ["optionIdentifier": "choice-a", "pollOptionText": "A"],
      ["optionIdentifier": "choice-b", "pollOptionText": "B"],
    ],
  ]
  let pollPayload = try PropertyListSerialization.data(
    fromPropertyList: [
      "url": try pollURL(queryName: "definition", object: definition).absoluteString
    ],
    format: .binary,
    options: 0
  )
  let pollBlob = Blob(bytes: [UInt8](pollPayload))
  let now = Date(timeIntervalSince1970: 1_700_000_000)

  try db.run(
    """
    INSERT INTO message(
      ROWID, handle_id, text, guid, associated_message_guid, associated_message_type,
      balloon_bundle_id, payload_data, message_summary_info, date, is_from_me, service
    )
    VALUES (1, 1, '', 'poll-row-guid', NULL, NULL, ?, ?, NULL, ?, 0, 'iMessage')
    """,
    testPollBundleID,
    pollBlob,
    TestDatabase.appleEpoch(now)
  )
  try db.run(
    """
    INSERT INTO message(
      ROWID, handle_id, text, guid, associated_message_guid, associated_message_type,
      balloon_bundle_id, payload_data, message_summary_info, date, is_from_me, service
    )
    VALUES (2, 1, 'hello', 'normal-row-guid', NULL, NULL, NULL, NULL, NULL, ?, 0, 'iMessage')
    """,
    TestDatabase.appleEpoch(now.addingTimeInterval(1))
  )
  try db.run("INSERT INTO chat_message_join(chat_id, message_id) VALUES (1, 1)")
  try db.run("INSERT INTO chat_message_join(chat_id, message_id) VALUES (1, 2)")

  let store = try MessageStore(connection: db, path: ":memory:")
  let messages = try store.messages(chatID: 1, limit: 10)

  let pollMessage = try #require(messages.first { $0.guid == "poll-row-guid" })
  #expect(pollMessage.poll?.kind == .created)
  #expect(pollMessage.poll?.question == "Pick one")
  #expect(pollMessage.poll?.options?.map(\.id) == ["choice-a", "choice-b"])

  let normalMessage = try #require(messages.first { $0.guid == "normal-row-guid" })
  #expect(normalMessage.poll == nil)
}

private func pollURL(queryName: String, object: [String: Any]) throws -> URL {
  let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  let encoded = data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
  var components = URLComponents()
  components.scheme = "messages-polls"
  components.host = "poll"
  components.queryItems = [
    URLQueryItem(name: "source", value: "sendMenu"),
    URLQueryItem(name: queryName, value: encoded),
  ]
  return try #require(components.url)
}

private func applePollEnvelopePayload(jsonObject: [String: Any], query: String = "") throws
  -> Data
{
  let json = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
  let encoded = json.base64EncodedString()
  let suffix = query.isEmpty ? "" : "?\(query)"
  let url = try #require(URL(string: "data:,\(encoded)\(suffix)"))
  return try NSKeyedArchiver.archivedData(
    withRootObject: [
      "URL": url,
      "sessionIdentifier": UUID(),
      "an": "Polls",
    ],
    requiringSecureCoding: false
  )
}
