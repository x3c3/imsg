import IMsgCore

func pluralSuffix(for count: Int) -> String {
  count == 1 ? "" : "s"
}

func displayName(for meta: AttachmentMeta) -> String {
  if !meta.transferName.isEmpty { return meta.transferName }
  if !meta.filename.isEmpty { return meta.filename }
  return "(unknown)"
}

func attachmentMetadataLine(for meta: AttachmentMeta) -> String {
  let name = displayName(for: meta)
  var line =
    "  attachment: name=\(name) mime=\(meta.mimeType) missing=\(meta.missing) path=\(meta.originalPath)"
  if let convertedPath = meta.convertedPath {
    let convertedMime = meta.convertedMimeType ?? ""
    line += " converted_mime=\(convertedMime) converted_path=\(convertedPath)"
  }
  return line
}

func pollDisplayText(for poll: MessagePollEvent) -> String {
  switch poll.kind {
  case .created:
    let question = poll.question ?? "poll"
    let options = poll.options?.map(\.text).joined(separator: " / ") ?? ""
    return options.isEmpty ? "[poll created] \(question)" : "[poll created] \(question): \(options)"
  case .vote:
    let participant = poll.vote?.participant ?? "someone"
    let option = poll.vote?.optionText ?? poll.vote?.optionID ?? "unknown option"
    let action = poll.vote?.eventType ?? "selected"
    return "[poll vote] \(participant) \(action) \(option)"
  case .unknown:
    return "[poll unknown]"
  }
}
