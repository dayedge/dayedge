import SwiftUI
import Domain

private struct DatePresentationFormatterKey: EnvironmentKey {
    static let defaultValue = DatePresentationFormatter()
}

extension EnvironmentValues {
    /// How dates are written, set at every window's root by
    /// `FormatProvider`.
    package var dateFormatter: DatePresentationFormatter {
        get { self[DatePresentationFormatterKey.self] }
        set { self[DatePresentationFormatterKey.self] = newValue }
    }
}

private struct TimeFormatKey: EnvironmentKey {
    static let defaultValue = TimeFormat.presentation(.system)
}

extension EnvironmentValues {
    /// How times are written (Settings → General → Time format), set at
    /// every window's root by `FormatProvider`.
    package var timeFormat: TimeFormat {
        get { self[TimeFormatKey.self] }
        set { self[TimeFormatKey.self] = newValue }
    }
}

/// Puts the time and date settings into the environment — live: a change
/// in Settings, or of the Mac's region, redraws every time and date shown.
package struct FormatProvider: ViewModifier {
    @AppStorage(GeneralSettings.timeFormatKey) private var preference = TimeFormatPreference.system.rawValue
    @AppStorage(GeneralSettings.dateFormatStandardKey) private var standardPattern = ""
    @AppStorage(GeneralSettings.dateFormatCompactKey) private var compactPattern = ""
    @State private var localeRevision = 0

    package func body(content: Content) -> some View {
        // swiftlint:disable:next redundant_discardable_let - `_ =` is not allowed in a view builder; reading these makes the body depend on them
        let _ = (localeRevision, standardPattern, compactPattern)
        content
            .environment(\.timeFormat, TimeFormat.presentation(TimeFormatPreference(rawValue: preference) ?? .system))
            .environment(\.dateFormatter, .current)
            .environment(\.locale, AppLocalization.formattingLocale(display: AppLocalization.displayLocale, region: .autoupdatingCurrent))
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                localeRevision += 1
            }
    }
}
