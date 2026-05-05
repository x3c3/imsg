import Foundation
import SQLite

public final class MessageStore: @unchecked Sendable {
  public static let appleEpochOffset: TimeInterval = 978_307_200

  public static var defaultPath: String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return NSString(string: home).appendingPathComponent("Library/Messages/chat.db")
  }

  public let path: String

  private let connection: Connection
  private let queue: DispatchQueue
  private let queueKey = DispatchSpecificKey<Void>()
  let hasAttributedBody: Bool
  let hasReactionColumns: Bool
  let hasThreadOriginatorGUIDColumn: Bool
  let hasDestinationCallerID: Bool
  let hasAudioMessageColumn: Bool
  let hasAttachmentUserInfo: Bool
  let hasBalloonBundleIDColumn: Bool
  let hasChatMessageJoinMessageDateColumn: Bool
  let hasChatAccountIDColumn: Bool
  let hasChatAccountLoginColumn: Bool
  let hasChatLastAddressedHandleColumn: Bool

  private struct URLBalloonDedupeEntry: Sendable {
    let rowID: Int64
    let date: Date
  }

  private static let urlBalloonDedupeWindow: TimeInterval = 90
  private static let urlBalloonDedupeRetention: TimeInterval = 10 * 60

  private var urlBalloonDedupe: [String: URLBalloonDedupeEntry] = [:]

  public init(path: String = MessageStore.defaultPath) throws {
    let normalized = NSString(string: path).expandingTildeInPath
    self.path = normalized
    self.queue = DispatchQueue(label: "imsg.db", qos: .userInitiated)
    self.queue.setSpecific(key: queueKey, value: ())
    do {
      let uri = URL(fileURLWithPath: normalized).absoluteString
      let location = Connection.Location.uri(uri, parameters: [.mode(.readOnly)])
      self.connection = try Connection(location, readonly: true)
      self.connection.busyTimeout = 5
      let messageColumns = MessageStore.tableColumns(connection: self.connection, table: "message")
      let attachmentColumns = MessageStore.tableColumns(
        connection: self.connection,
        table: "attachment"
      )
      let chatMessageJoinColumns = MessageStore.tableColumns(
        connection: self.connection,
        table: "chat_message_join"
      )
      let chatColumns = MessageStore.tableColumns(connection: self.connection, table: "chat")
      self.hasAttributedBody = messageColumns.contains("attributedbody")
      self.hasReactionColumns = MessageStore.reactionColumnsPresent(in: messageColumns)
      self.hasThreadOriginatorGUIDColumn = messageColumns.contains("thread_originator_guid")
      self.hasDestinationCallerID = messageColumns.contains("destination_caller_id")
      self.hasAudioMessageColumn = messageColumns.contains("is_audio_message")
      self.hasAttachmentUserInfo = attachmentColumns.contains("user_info")
      self.hasBalloonBundleIDColumn = messageColumns.contains("balloon_bundle_id")
      self.hasChatMessageJoinMessageDateColumn = chatMessageJoinColumns.contains("message_date")
      self.hasChatAccountIDColumn = chatColumns.contains("account_id")
      self.hasChatAccountLoginColumn = chatColumns.contains("account_login")
      self.hasChatLastAddressedHandleColumn = chatColumns.contains("last_addressed_handle")
    } catch {
      throw MessageStore.enhance(error: error, path: normalized)
    }
  }

  init(
    connection: Connection,
    path: String,
    hasAttributedBody: Bool? = nil,
    hasReactionColumns: Bool? = nil,
    hasThreadOriginatorGUIDColumn: Bool? = nil,
    hasDestinationCallerID: Bool? = nil,
    hasAudioMessageColumn: Bool? = nil,
    hasAttachmentUserInfo: Bool? = nil,
    hasBalloonBundleIDColumn: Bool? = nil,
    hasChatMessageJoinMessageDateColumn: Bool? = nil,
    hasChatAccountIDColumn: Bool? = nil,
    hasChatAccountLoginColumn: Bool? = nil,
    hasChatLastAddressedHandleColumn: Bool? = nil
  ) throws {
    self.path = path
    self.queue = DispatchQueue(label: "imsg.db.test", qos: .userInitiated)
    self.queue.setSpecific(key: queueKey, value: ())
    self.connection = connection
    self.connection.busyTimeout = 5
    let messageColumns = MessageStore.tableColumns(connection: connection, table: "message")
    let attachmentColumns = MessageStore.tableColumns(connection: connection, table: "attachment")
    let chatMessageJoinColumns = MessageStore.tableColumns(
      connection: connection,
      table: "chat_message_join"
    )
    let chatColumns = MessageStore.tableColumns(connection: connection, table: "chat")
    if let hasAttributedBody {
      self.hasAttributedBody = hasAttributedBody
    } else {
      self.hasAttributedBody = messageColumns.contains("attributedbody")
    }
    if let hasReactionColumns {
      self.hasReactionColumns = hasReactionColumns
    } else {
      self.hasReactionColumns = MessageStore.reactionColumnsPresent(in: messageColumns)
    }
    if let hasThreadOriginatorGUIDColumn {
      self.hasThreadOriginatorGUIDColumn = hasThreadOriginatorGUIDColumn
    } else {
      self.hasThreadOriginatorGUIDColumn = messageColumns.contains("thread_originator_guid")
    }
    if let hasDestinationCallerID {
      self.hasDestinationCallerID = hasDestinationCallerID
    } else {
      self.hasDestinationCallerID = messageColumns.contains("destination_caller_id")
    }
    if let hasAudioMessageColumn {
      self.hasAudioMessageColumn = hasAudioMessageColumn
    } else {
      self.hasAudioMessageColumn = messageColumns.contains("is_audio_message")
    }
    if let hasAttachmentUserInfo {
      self.hasAttachmentUserInfo = hasAttachmentUserInfo
    } else {
      self.hasAttachmentUserInfo = attachmentColumns.contains("user_info")
    }
    if let hasBalloonBundleIDColumn {
      self.hasBalloonBundleIDColumn = hasBalloonBundleIDColumn
    } else {
      self.hasBalloonBundleIDColumn = messageColumns.contains("balloon_bundle_id")
    }
    if let hasChatMessageJoinMessageDateColumn {
      self.hasChatMessageJoinMessageDateColumn = hasChatMessageJoinMessageDateColumn
    } else {
      self.hasChatMessageJoinMessageDateColumn = chatMessageJoinColumns.contains("message_date")
    }
    if let hasChatAccountIDColumn {
      self.hasChatAccountIDColumn = hasChatAccountIDColumn
    } else {
      self.hasChatAccountIDColumn = chatColumns.contains("account_id")
    }
    if let hasChatAccountLoginColumn {
      self.hasChatAccountLoginColumn = hasChatAccountLoginColumn
    } else {
      self.hasChatAccountLoginColumn = chatColumns.contains("account_login")
    }
    if let hasChatLastAddressedHandleColumn {
      self.hasChatLastAddressedHandleColumn = hasChatLastAddressedHandleColumn
    } else {
      self.hasChatLastAddressedHandleColumn = chatColumns.contains("last_addressed_handle")
    }
  }

  func withConnection<T>(_ block: (Connection) throws -> T) throws -> T {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      return try block(connection)
    }
    return try queue.sync {
      try block(connection)
    }
  }

  func shouldSkipURLBalloonDuplicate(
    chatID: Int64,
    sender: String,
    text: String,
    isFromMe: Bool,
    date: Date,
    rowID: Int64
  ) -> Bool {
    guard !text.isEmpty else { return false }

    pruneURLBalloonDedupe(referenceDate: date)

    let key = "\(chatID)|\(isFromMe ? 1 : 0)|\(sender)|\(text)"
    let current = URLBalloonDedupeEntry(rowID: rowID, date: date)
    guard let previous = urlBalloonDedupe[key] else {
      urlBalloonDedupe[key] = current
      return false
    }

    urlBalloonDedupe[key] = current
    if rowID <= previous.rowID {
      return true
    }
    return date.timeIntervalSince(previous.date) <= MessageStore.urlBalloonDedupeWindow
  }

  private func pruneURLBalloonDedupe(referenceDate: Date) {
    guard !urlBalloonDedupe.isEmpty else { return }
    let cutoff = referenceDate.addingTimeInterval(-MessageStore.urlBalloonDedupeRetention)
    urlBalloonDedupe = urlBalloonDedupe.filter { $0.value.date >= cutoff }
  }
}

extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

extension MessageStore {
  public func attachments(
    for messageID: Int64,
    options: AttachmentQueryOptions = .default
  ) throws -> [AttachmentMeta] {
    let sql = """
      SELECT a.filename AS filename, a.transfer_name AS transfer_name, a.uti AS uti,
             a.mime_type AS mime_type, a.total_bytes AS total_bytes, a.is_sticker AS is_sticker
      FROM message_attachment_join maj
      JOIN attachment a ON a.ROWID = maj.attachment_id
      WHERE maj.message_id = ?
      """
    return try withConnection { db in
      var metas: [AttachmentMeta] = []
      let rows = try db.prepareRowIterator(sql, bindings: [messageID])
      while let row = try rows.failableNext() {
        let filename = try stringValue(row, "filename")
        let transferName = try stringValue(row, "transfer_name")
        let uti = try stringValue(row, "uti")
        let mimeType = try stringValue(row, "mime_type")
        let totalBytes = try int64Value(row, "total_bytes") ?? 0
        let isSticker = try boolValue(row, "is_sticker")
        metas.append(
          AttachmentResolver.metadata(
            filename: filename,
            transferName: transferName,
            uti: uti,
            mimeType: mimeType,
            totalBytes: totalBytes,
            isSticker: isSticker,
            options: options
          ))
      }
      return metas
    }
  }

  func audioTranscription(for messageID: Int64) throws -> String? {
    guard hasAttachmentUserInfo else { return nil }
    let sql = """
      SELECT a.user_info
      FROM message_attachment_join maj
      JOIN attachment a ON a.ROWID = maj.attachment_id
      WHERE maj.message_id = ?
      LIMIT 1
      """
    return try withConnection { db in
      let rows = try db.prepareRowIterator(sql, bindings: [messageID])
      while let row = try rows.failableNext() {
        let info = try dataValue(row, "user_info")
        guard !info.isEmpty else { continue }
        if let transcription = parseAudioTranscription(from: info) {
          return transcription
        }
      }
      return nil
    }
  }

  private func parseAudioTranscription(from data: Data) -> String? {
    do {
      let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      )
      guard
        let dict = plist as? [String: Any],
        let transcription = dict["audio-transcription"] as? String,
        !transcription.isEmpty
      else {
        return nil
      }
      return transcription
    } catch {
      return nil
    }
  }

  public func maxRowID() throws -> Int64 {
    return try withConnection { db in
      let value = try db.scalar("SELECT MAX(ROWID) FROM message")
      return int64Value(value) ?? 0
    }
  }

  public func reactions(for messageID: Int64) throws -> [Reaction] {
    guard hasReactionColumns else { return [] }
    // Reactions are stored as messages with associated_message_type in range 2000-2006
    // 2000-2005 are standard tapbacks, 2006 is custom emoji reactions
    // They reference the original message via associated_message_guid which has format "p:X/GUID"
    // where X is the part index (0 for single-part messages) and GUID matches the original message's guid
    let bodyColumn = hasAttributedBody ? "r.attributedBody" : "NULL"
    let sql = """
      SELECT r.ROWID AS reaction_rowid, r.associated_message_type AS associated_message_type,
             h.id AS sender, r.is_from_me AS is_from_me, r.date AS date, IFNULL(r.text, '') AS text,
             \(bodyColumn) AS body
      FROM message m
      JOIN message r ON r.associated_message_guid = m.guid
        OR r.associated_message_guid LIKE '%/' || m.guid
      LEFT JOIN handle h ON r.handle_id = h.ROWID
      WHERE m.ROWID = ?
        AND m.guid IS NOT NULL
        AND m.guid != ''
        AND r.associated_message_type >= 2000
        AND r.associated_message_type <= 3006
      ORDER BY r.date ASC
      """
    return try withConnection { db in
      var reactions: [Reaction] = []
      var reactionIndex: [ReactionKey: Int] = [:]
      let rows = try db.prepareRowIterator(sql, bindings: [messageID])
      while let row = try rows.failableNext() {
        let rowID = try int64Value(row, "reaction_rowid") ?? 0
        let typeValue = try intValue(row, "associated_message_type") ?? 0
        let sender = try stringValue(row, "sender")
        let isFromMe = try boolValue(row, "is_from_me")
        let date = try appleDate(from: int64Value(row, "date"))
        let text = try stringValue(row, "text")
        let body = try dataValue(row, "body")
        let resolvedText = text.isEmpty ? TypedStreamParser.parseAttributedBody(body) : text

        if ReactionType.isReactionRemove(typeValue) {
          let customEmoji = typeValue == 3006 ? extractCustomEmoji(from: resolvedText) : nil
          let reactionType = ReactionType.fromRemoval(typeValue, customEmoji: customEmoji)
          if let reactionType {
            let key = ReactionKey(sender: sender, isFromMe: isFromMe, reactionType: reactionType)
            if let index = reactionIndex.removeValue(forKey: key) {
              reactions.remove(at: index)
              reactionIndex = ReactionKey.reindex(reactions: reactions)
            }
            continue
          }
          if typeValue == 3006 {
            if let index = reactions.firstIndex(where: {
              $0.sender == sender && $0.isFromMe == isFromMe && $0.reactionType.isCustom
            }) {
              reactions.remove(at: index)
              reactionIndex = ReactionKey.reindex(reactions: reactions)
            }
          }
          continue
        }

        let customEmoji: String? = typeValue == 2006 ? extractCustomEmoji(from: resolvedText) : nil
        guard let reactionType = ReactionType(rawValue: typeValue, customEmoji: customEmoji) else {
          continue
        }

        let key = ReactionKey(sender: sender, isFromMe: isFromMe, reactionType: reactionType)
        if let index = reactionIndex[key] {
          reactions[index] = Reaction(
            rowID: rowID,
            reactionType: reactionType,
            sender: sender,
            isFromMe: isFromMe,
            date: date,
            associatedMessageID: messageID
          )
        } else {
          reactionIndex[key] = reactions.count
          reactions.append(
            Reaction(
              rowID: rowID,
              reactionType: reactionType,
              sender: sender,
              isFromMe: isFromMe,
              date: date,
              associatedMessageID: messageID
            ))
        }
      }
      return reactions
    }
  }

  /// Extract custom emoji from reaction message text like "Reacted 🎉 to "original message""
  func extractCustomEmoji(from text: String) -> String? {
    // Format: "Reacted X to "..." where X is the emoji. Fallback to first emoji in text.
    guard
      let reactedRange = text.range(of: "Reacted "),
      let toRange = text.range(of: " to ", range: reactedRange.upperBound..<text.endIndex)
    else {
      return extractFirstEmoji(from: text)
    }
    let emoji = String(text[reactedRange.upperBound..<toRange.lowerBound])
    return emoji.isEmpty ? extractFirstEmoji(from: text) : emoji
  }

  private func extractFirstEmoji(from text: String) -> String? {
    for character in text {
      if character.unicodeScalars.contains(where: {
        $0.properties.isEmojiPresentation || $0.properties.isEmoji
      }) {
        return String(character)
      }
    }
    return nil
  }

  private struct ReactionKey: Hashable {
    let sender: String
    let isFromMe: Bool
    let reactionType: ReactionType

    static func reindex(reactions: [Reaction]) -> [ReactionKey: Int] {
      var index: [ReactionKey: Int] = [:]
      for (offset, reaction) in reactions.enumerated() {
        let key = ReactionKey(
          sender: reaction.sender,
          isFromMe: reaction.isFromMe,
          reactionType: reaction.reactionType
        )
        index[key] = offset
      }
      return index
    }
  }
}
