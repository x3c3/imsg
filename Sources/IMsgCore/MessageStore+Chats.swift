import Foundation
import SQLite

extension MessageStore {
  public func listChats(limit: Int) throws -> [Chat] {
    let accountIDColumn = hasChatAccountIDColumn ? "IFNULL(c.account_id, '')" : "''"
    let accountLoginColumn = hasChatAccountLoginColumn ? "IFNULL(c.account_login, '')" : "''"
    let lastAddressedHandleColumn =
      hasChatLastAddressedHandleColumn ? "IFNULL(c.last_addressed_handle, '')" : "''"
    let sql: String
    if hasChatMessageJoinMessageDateColumn {
      sql = """
        SELECT c.ROWID AS chat_rowid, IFNULL(c.display_name, c.chat_identifier) AS name,
               c.chat_identifier AS chat_identifier, c.service_name AS service_name,
               MAX(cmj.message_date) AS last_date,
               \(accountIDColumn) AS account_id,
               \(accountLoginColumn) AS account_login,
               \(lastAddressedHandleColumn) AS last_addressed_handle
        FROM chat c
        JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
        GROUP BY c.ROWID
        ORDER BY last_date DESC
        LIMIT ?
        """
    } else {
      sql = """
        SELECT c.ROWID AS chat_rowid, IFNULL(c.display_name, c.chat_identifier) AS name,
               c.chat_identifier AS chat_identifier, c.service_name AS service_name,
               MAX(m.date) AS last_date,
               \(accountIDColumn) AS account_id,
               \(accountLoginColumn) AS account_login,
               \(lastAddressedHandleColumn) AS last_addressed_handle
        FROM chat c
        JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
        JOIN message m ON m.ROWID = cmj.message_id
        GROUP BY c.ROWID
        ORDER BY last_date DESC
        LIMIT ?
        """
    }
    return try withConnection { db in
      var chats: [Chat] = []
      let rows = try db.prepareRowIterator(sql, bindings: [limit])
      while let row = try rows.failableNext() {
        chats.append(
          Chat(
            id: try int64Value(row, "chat_rowid") ?? 0,
            identifier: try stringValue(row, "chat_identifier"),
            name: try stringValue(row, "name"),
            service: try stringValue(row, "service_name"),
            lastMessageAt: try appleDate(from: int64Value(row, "last_date")),
            accountID: try stringValue(row, "account_id").nilIfEmpty,
            accountLogin: try stringValue(row, "account_login").nilIfEmpty,
            lastAddressedHandle: try stringValue(row, "last_addressed_handle").nilIfEmpty
          ))
      }
      return chats
    }
  }

  public func chatInfo(chatID: Int64) throws -> ChatInfo? {
    let accountIDColumn = hasChatAccountIDColumn ? "IFNULL(c.account_id, '')" : "''"
    let accountLoginColumn = hasChatAccountLoginColumn ? "IFNULL(c.account_login, '')" : "''"
    let lastAddressedHandleColumn =
      hasChatLastAddressedHandleColumn ? "IFNULL(c.last_addressed_handle, '')" : "''"
    let sql = """
      SELECT c.ROWID AS chat_rowid, IFNULL(c.chat_identifier, '') AS identifier, IFNULL(c.guid, '') AS guid,
             IFNULL(c.display_name, c.chat_identifier) AS name, IFNULL(c.service_name, '') AS service,
             \(accountIDColumn) AS account_id,
             \(accountLoginColumn) AS account_login,
             \(lastAddressedHandleColumn) AS last_addressed_handle
      FROM chat c
      WHERE c.ROWID = ?
      LIMIT 1
      """
    return try withConnection { db in
      let rows = try db.prepareRowIterator(sql, bindings: [chatID])
      while let row = try rows.failableNext() {
        return ChatInfo(
          id: try int64Value(row, "chat_rowid") ?? 0,
          identifier: try stringValue(row, "identifier"),
          guid: try stringValue(row, "guid"),
          name: try stringValue(row, "name"),
          service: try stringValue(row, "service"),
          accountID: try stringValue(row, "account_id").nilIfEmpty,
          accountLogin: try stringValue(row, "account_login").nilIfEmpty,
          lastAddressedHandle: try stringValue(row, "last_addressed_handle").nilIfEmpty
        )
      }
      return nil
    }
  }

  public func participants(chatID: Int64) throws -> [String] {
    let sql = """
      SELECT h.id
      FROM chat_handle_join chj
      JOIN handle h ON h.ROWID = chj.handle_id
      WHERE chj.chat_id = ?
      ORDER BY h.id ASC
      """
    return try withConnection { db in
      var results: [String] = []
      var seen = Set<String>()
      let rows = try db.prepareRowIterator(sql, bindings: [chatID])
      while let row = try rows.failableNext() {
        let handle = try stringValue(row, "id")
        if handle.isEmpty { continue }
        if seen.insert(handle).inserted {
          results.append(handle)
        }
      }
      return results
    }
  }
}
