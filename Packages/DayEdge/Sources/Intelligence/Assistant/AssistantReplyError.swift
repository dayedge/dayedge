import Foundation

/// Why a reply failed, in words the user can act on. Backends translate
/// their own errors into these; anything else is "something went wrong".
package enum AssistantReplyError: Error, Equatable {
    /// Too much for the model's window, even without earlier messages.
    case tooLong
    /// The model is busy (too many requests at once).
    case busy
    /// The model isn't available right now (not downloaded, turned off).
    case unavailable
    /// The model declined to answer.
    case declined
    /// The model doesn't speak this language.
    case unsupportedLanguage

    package static func message(for error: Error) -> String {
        switch error as? AssistantReplyError {
        case .tooLong?:
            return L10n.tr("assistantreplyerror.too.long",
                           "That's too much for the on-device model — try a narrower question, or choose a provider in Settings → Intelligence.")
        case .busy?: return L10n.tr("assistantreplyerror.busy", "The on-device model is busy. Try again in a moment.")
        case .unavailable?: return L10n.tr("assistantreplyerror.unavailable", "The on-device model isn't available right now.")
        case .declined?: return L10n.tr("assistantreplyerror.declined", "The on-device model can't answer that.")
        case .unsupportedLanguage?:
            return L10n.tr("assistantreplyerror.unsupported.language",
                           "The on-device model doesn't support this language yet — try English, or choose a provider in Settings → Intelligence.")
        case nil: return L10n.tr("chatsession.something.went.wrong.try.again", "Something went wrong. Try again.")
        }
    }
}

/// One retry for a reply that overflowed the window: again without the
/// earlier messages — everything else is capped, so that fits; failing
/// twice is `.tooLong`.
package enum OnDeviceRetry {
    package static func run(isOverflow: (Error) -> Bool, _ attempt: (_ withHistory: Bool) async throws -> Void) async throws {
        do {
            try await attempt(true)
        } catch where isOverflow(error) {
            do {
                try await attempt(false)
            } catch where isOverflow(error) {
                throw AssistantReplyError.tooLong
            }
        }
    }
}
