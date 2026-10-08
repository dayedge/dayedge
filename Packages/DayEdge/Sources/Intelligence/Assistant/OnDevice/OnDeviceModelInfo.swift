import Foundation
#if HAS_MACOS26_SDK
import FoundationModels
#endif

/// What Settings shows about Apple's on-device model — read from
/// FoundationModels at runtime, never written down here; empty where this
/// macOS or build can't tell.
package struct OnDeviceModelInfo: Equatable, Sendable {
    /// The model's window, in tokens.
    package var contextSize: Int?
    /// The languages it answers in, by name in the app's language, sorted.
    package var languages: [String] = []

    package static func current(in locale: Locale) -> OnDeviceModelInfo {
        #if HAS_MACOS26_SDK
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            let names = Set(model.supportedLanguages.compactMap { language in
                language.languageCode.flatMap { locale.localizedString(forLanguageCode: $0.identifier) }
            })
            return OnDeviceModelInfo(contextSize: model.contextSize, languages: names.sorted { $0.localizedCompare($1) == .orderedAscending })
        }
        #endif
        return OnDeviceModelInfo()
    }
}
