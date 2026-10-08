import Foundation

/// Turns whatever a source/account reports into something fit for the UI.
/// Some accounts surface only an identifier ("07AA7559-F0D4-…"); those never
/// reach the screen — a friendly name for the account kind replaces them.
package enum SourceDisplayName {
    package static func name(rawTitle: String?, kind: SourceKind) -> String {
        let trimmed = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty || isTechnical(trimmed) ? fallback(for: kind) : trimmed
    }

    package static func fallback(for kind: SourceKind) -> String {
        switch kind {
        case .iCloud: return "iCloud"
        case .exchange: return "Exchange"
        case .google: return "Google"
        case .calDAV: return "CalDAV"
        case .local: return L10n.tr("sourcedisplayname.on.my.mac", "On My Mac")
        case .subscribed: return L10n.tr("sourcedisplayname.subscribed", "Subscribed")
        case .birthdays: return L10n.tr("sourcedisplayname.birthdays", "Birthdays")
        case .other: return L10n.tr("sourcedisplayname.other", "Other")
        }
    }

    /// UUID-like or long hex strings — identifiers, not names.
    package static func isTechnical(_ text: String) -> Bool {
        if UUID(uuidString: text) != nil { return true }
        let hexOrDash = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        return text.count >= 24 && text.unicodeScalars.allSatisfy(hexOrDash.contains)
    }
}
