import Foundation

/// The language typed text is read in: Quick Add, the palette's dates and search.
///
/// English only for now, while parsing is in beta. The choice is made here alone, so reading in another language is
/// adding it to `supported`; following the system then works as it is, and a choice in Settings is passing it as
/// `override` from `current()`.
package enum ParsingLanguage {
    /// The languages the app reads, as language codes the library takes ("en"). The first is the fallback.
    package static let supported = ["en"]

    /// The language to read in now.
    package static func current() -> String {
        resolve(override: nil, preferred: Locale.preferredLanguages)
    }

    /// `override` (a Settings choice) if the app reads it; else the first of the user's `preferred` languages
    /// ("pl-PL", "en-GB") that it reads; else the fallback.
    package static func resolve(override: String?, preferred: [String], supported: [String] = supported) -> String {
        let candidates = [override].compactMap { $0 } + preferred
        let match = candidates.lazy
            .compactMap { Locale.Language(identifier: $0).languageCode?.identifier }
            .first { supported.contains($0) }
        return match ?? supported[0]
    }
}
