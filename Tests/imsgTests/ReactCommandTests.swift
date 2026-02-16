import Commander
import Foundation
import Testing

@testable import IMsgCore
@testable import imsg

@Test
func reactCommandRejectsMultiCharacterEmojiInput() async {
  do {
    let path = try CommandTestDatabase.makePath()
    let values = ParsedValues(
      positional: [],
      options: ["db": [path], "chatID": ["1"], "reaction": ["🎉 party"]],
      flags: []
    )
    let runtime = RuntimeOptions(parsedValues: values)
    try await ReactCommand.run(values: values, runtime: runtime)
    #expect(Bool(false))
  } catch let error as IMsgError {
    switch error {
    case .invalidReaction(let value):
      #expect(value == "🎉 party")
    default:
      #expect(Bool(false))
    }
  } catch {
    #expect(Bool(false))
  }
}

@Test
func reactCommandBuildsParameterizedAppleScriptForStandardTapback() async throws {
  let path = try CommandTestDatabase.makePath()
  let values = ParsedValues(
    positional: [],
    options: ["db": [path], "chatID": ["1"], "reaction": ["like"]],
    flags: []
  )
  let runtime = RuntimeOptions(parsedValues: values)
  var capturedScript = ""
  var capturedArguments: [String] = []
  try await ReactCommand.run(
    values: values,
    runtime: runtime,
    appleScriptRunner: { source, arguments in
      capturedScript = source
      capturedArguments = arguments
    }
  )
  #expect(capturedArguments == ["iMessage;+;chat123", "Test Chat", "2"])
  #expect(capturedScript.contains("on run argv"))
  #expect(capturedScript.contains("keystroke \"f\" using command down"))
  #expect(capturedScript.contains("set targetChat to chat id chatGUID"))
  #expect(capturedScript.contains("keystroke reactionKey"))
  #expect(capturedScript.contains("chat123") == false)
}

@Test
func reactCommandBuildsParameterizedAppleScriptForCustomEmoji() async throws {
  let path = try CommandTestDatabase.makePath()
  let values = ParsedValues(
    positional: [],
    options: ["db": [path], "chatID": ["1"], "reaction": ["🎉"]],
    flags: []
  )
  let runtime = RuntimeOptions(parsedValues: values)
  var capturedScript = ""
  var capturedArguments: [String] = []
  try await ReactCommand.run(
    values: values,
    runtime: runtime,
    appleScriptRunner: { source, arguments in
      capturedScript = source
      capturedArguments = arguments
    }
  )
  #expect(capturedArguments == ["iMessage;+;chat123", "Test Chat", "🎉"])
  #expect(capturedScript.contains("on run argv"))
  #expect(capturedScript.contains("keystroke customEmoji"))
  #expect(capturedScript.contains("key code 36"))
  #expect(capturedScript.contains("chat123") == false)
}
