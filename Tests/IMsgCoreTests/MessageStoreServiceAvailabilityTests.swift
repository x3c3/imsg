import Foundation
import SQLite
import Testing

@testable import IMsgCore

private func makeAvailabilityStore() throws -> (MessageStore, Connection) {
  let db = try Connection(.inMemory)
  try db.execute(
    """
    CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT, service TEXT);
    """
  )
  try db.execute(
    """
    CREATE TABLE message (
      ROWID INTEGER PRIMARY KEY,
      handle_id INTEGER,
      error INTEGER DEFAULT 0
    );
    """
  )
  let store = try MessageStore(connection: db, path: ":memory:")
  return (store, db)
}

private func insertHandle(_ db: Connection, rowID: Int64, id: String, service: String) throws {
  try db.run(
    "INSERT INTO handle(ROWID, id, service) VALUES (?, ?, ?)",
    rowID, id, service
  )
}

private func insertMessage(_ db: Connection, handleID: Int64, error: Int64 = 0) throws {
  try db.run(
    "INSERT INTO message(handle_id, error) VALUES (?, ?)",
    handleID, error
  )
}

@Test
func preferredServiceReturnsIMessageForNonErroredIMessageHandle() throws {
  let (store, db) = try makeAvailabilityStore()
  try insertHandle(db, rowID: 1, id: "+15551234567", service: "iMessage")
  try insertMessage(db, handleID: 1)

  #expect(try store.preferredService(forHandle: "+15551234567") == .imessage)
}

@Test
func preferredServiceMatchesPhoneFormatVariants() throws {
  let (store, db) = try makeAvailabilityStore()
  // Stored without country code; query with +1 form.
  try insertHandle(db, rowID: 1, id: "5551234567", service: "iMessage")
  try insertMessage(db, handleID: 1)

  #expect(try store.preferredService(forHandle: "+15551234567") == .imessage)
}

@Test
func preferredServiceReturnsSMSWhenOnlySMSHistory() throws {
  let (store, db) = try makeAvailabilityStore()
  try insertHandle(db, rowID: 1, id: "+15551234567", service: "SMS")
  try insertMessage(db, handleID: 1)

  #expect(try store.preferredService(forHandle: "+15551234567") == .sms)
}

@Test
func preferredServiceNormalizesHandleWithRegion() throws {
  let (store, db) = try makeAvailabilityStore()
  try insertHandle(db, rowID: 1, id: "+447700900000", service: "SMS")
  try insertMessage(db, handleID: 1)

  #expect(try store.preferredService(forHandle: "07700 900000", region: "GB") == .sms)
}

@Test
func preferredServiceFallsBackToSMSWhenIMessageOnlyErrored() throws {
  let (store, db) = try makeAvailabilityStore()
  try insertHandle(db, rowID: 1, id: "+15551234567", service: "iMessage")
  try insertMessage(db, handleID: 1, error: 1)
  try insertHandle(db, rowID: 2, id: "+15551234567", service: "SMS")
  try insertMessage(db, handleID: 2)

  #expect(try store.preferredService(forHandle: "+15551234567") == .sms)
}

@Test
func preferredServiceReturnsUnknownForNewContact() throws {
  let (store, _) = try makeAvailabilityStore()

  #expect(try store.preferredService(forHandle: "+15559998888") == .unknown)
}

@Test
func preferredServiceMatchesEmailHandle() throws {
  let (store, db) = try makeAvailabilityStore()
  try insertHandle(db, rowID: 1, id: "friend@example.com", service: "iMessage")
  try insertMessage(db, handleID: 1)

  #expect(try store.preferredService(forHandle: "Friend@Example.com") == .imessage)
}

@Test
func handleCandidatesExpandsTenDigitNumber() {
  let candidates = MessageStore.handleCandidates("(555) 123-4567")
  #expect(candidates.contains("5551234567"))
  #expect(candidates.contains("15551234567"))
  #expect(candidates.contains("+15551234567"))
}

@Test
func handleCandidatesLowercasesEmail() {
  let candidates = MessageStore.handleCandidates("Friend@Example.com")
  #expect(candidates == ["friend@example.com"])
}
