import Foundation
import Testing

@testable import IMsgCore

#if os(macOS)
  private final class RunnerSpy: @unchecked Sendable {
    private(set) var services: [String] = []
    var failOnFirst: Bool = false

    func run(_ source: String, _ arguments: [String]) throws {
      // arguments[2] is the service rawValue.
      let service = arguments[2]
      services.append(service)
      if failOnFirst && services.count == 1 {
        throw IMsgError.appleScriptFailure("simulated iMessage failure")
      }
    }
  }

  @Test
  func smsFallbackRetriesOverSMSForPhoneRecipient() throws {
    let spy = RunnerSpy()
    spy.failOnFirst = true
    let sender = MessageSender(runner: spy.run)
    let options = MessageSendOptions(
      recipient: "+15551234567",
      text: "hi",
      service: .auto
    )

    try sender.send(options)

    #expect(spy.services == ["imessage", "sms"])
  }

  @Test
  func smsFallbackDoesNotOverrideExplicitIMessage() throws {
    let spy = RunnerSpy()
    spy.failOnFirst = true
    let sender = MessageSender(runner: spy.run)
    let options = MessageSendOptions(
      recipient: "+15551234567",
      text: "hi",
      service: .imessage,
      allowSMSFallback: true
    )

    #expect(throws: IMsgError.self) {
      try sender.send(options)
    }
    #expect(spy.services == ["imessage"])
  }

  @Test
  func smsFallbackDisabledRethrowsOriginalError() throws {
    let spy = RunnerSpy()
    spy.failOnFirst = true
    let sender = MessageSender(runner: spy.run)
    let options = MessageSendOptions(
      recipient: "+15551234567",
      text: "hi",
      service: .auto,
      allowSMSFallback: false
    )

    #expect(throws: IMsgError.self) {
      try sender.send(options)
    }
    #expect(spy.services == ["imessage"])
  }

  @Test
  func smsFallbackDoesNotEngageForEmailRecipient() throws {
    let spy = RunnerSpy()
    spy.failOnFirst = true
    let sender = MessageSender(runner: spy.run)
    let options = MessageSendOptions(
      recipient: "friend@example.com",
      text: "hi",
      service: .imessage,
      allowSMSFallback: true
    )

    #expect(throws: IMsgError.self) {
      try sender.send(options)
    }
    #expect(spy.services == ["imessage"])
  }

  @Test
  func smsFallbackDoesNotEngageForChatTarget() throws {
    let spy = RunnerSpy()
    spy.failOnFirst = true
    let sender = MessageSender(runner: spy.run)
    let options = MessageSendOptions(
      recipient: "",
      text: "hi",
      service: .imessage,
      chatGUID: "iMessage;+;chat123",
      allowSMSFallback: true
    )

    #expect(throws: IMsgError.self) {
      try sender.send(options)
    }
    #expect(spy.services == ["imessage"])
  }

  @Test
  func smsFallbackDoesNotEngageForAttachmentSend() throws {
    let spy = RunnerSpy()
    spy.failOnFirst = true
    let sender = MessageSender(
      runner: spy.run,
      attachmentsSubdirectoryProvider: {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      }
    )
    let attachment = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try Data("photo".utf8).write(to: attachment)
    defer { try? FileManager.default.removeItem(at: attachment) }
    let options = MessageSendOptions(
      recipient: "+15551234567",
      text: "hi",
      attachmentPath: attachment.path,
      service: .auto,
      allowSMSFallback: true
    )

    #expect(throws: IMsgError.self) {
      try sender.send(options)
    }
    #expect(spy.services == ["imessage"])
  }

  @Test
  func successfulFirstSendDoesNotRetry() throws {
    let spy = RunnerSpy()
    let sender = MessageSender(runner: spy.run)
    let options = MessageSendOptions(
      recipient: "+15551234567",
      text: "hi",
      service: .imessage,
      allowSMSFallback: true
    )

    try sender.send(options)

    #expect(spy.services == ["imessage"])
  }
#endif
