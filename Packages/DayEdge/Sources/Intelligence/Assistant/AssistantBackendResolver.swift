import Foundation

/// Picks who answers Ask, from the user's Intelligence settings,
/// and configures it for that model: the provider they opted into (with
/// their key and model), else Apple's on-device model, else a plain
/// explanation of what's missing. Each gets its own prompt tier and tool
/// style; this is the one place tools are registered.
package enum AssistantBackendResolver {
    package enum Choice: Equatable {
        case provider(AssistantProviderKind)
        case appleOnDevice
        case unavailable
    }

    /// The pure decision. A provider only when it's chosen and complete —
    /// never implicitly.
    package static func choice(settings: AssistantSettings, appleAvailable: Bool, remoteModelsBuilt: Bool = remoteModelsBuilt) -> Choice {
        if let ready = settings.readyProvider, remoteModelsBuilt { return .provider(ready.kind) }
        if appleAvailable { return .appleOnDevice }
        return .unavailable
    }

    /// `toolContext` is this conversation's (its references included).
    package static func resolve(
        toolContext: AssistantToolContext,
        settings: AssistantSettings,
        appleAvailable: Bool = appleOnDeviceAvailable
    ) -> any ChatResponding {
        switch choice(settings: settings, appleAvailable: appleAvailable) {
        case .provider(let kind):
            #if canImport(Tachikoma)
            if let ready = settings.readyProvider {
                var remote = toolContext
                remote.offersAlwaysAllow = true
                return TachikomaBackend.provider(
                    kind, configuration: ready.configuration,
                    tools: AssistantToolbox.readOnly(remote) + AssistantToolbox.changes(remote),
                    instructions: { [calendar = toolContext.calendar] now in AssistantInstructions.full(now: now, calendar: calendar) }
                )
            }
            #endif
            _ = kind
            return UnavailableChatResponder.explaining(settings)
        case .appleOnDevice:
            #if HAS_MACOS26_SDK
            if #available(macOS 26, *) {
                // The small model gets plain tool results: it doesn't use references.
                var plain = toolContext
                plain.showsReferences = false
                // The small model never gets "Always allow": it asks every time.
                plain.offersAlwaysAllow = false
                plain.isCompact = true
                let calendar = toolContext.calendar
                return AppleFoundationModelsBackend(
                    tools: AssistantToolbox.readOnly(plain) + AssistantToolbox.changes(plain),
                    instructions: { now in AssistantInstructions.onDevice(now: now, calendar: calendar) },
                    now: toolContext.now
                )
            }
            #endif
            return UnavailableChatResponder.explaining(settings)
        case .unavailable:
            return UnavailableChatResponder.explaining(settings)
        }
    }

    package static var appleOnDeviceAvailable: Bool { onDeviceStatus == .ready }

    /// Apple's on-device model on this Mac, for Settings → Intelligence.
    package static var onDeviceStatus: OnDeviceModelStatus {
        #if HAS_MACOS26_SDK
        if #available(macOS 26, *) { return AppleFoundationModelsBackend.status }
        return .unsupported
        #else
        return .notInThisBuild
        #endif
    }

    /// Whether this build includes Tachikoma (it needs Swift 6.2).
    package static var remoteModelsBuilt: Bool {
        #if canImport(Tachikoma)
        return true
        #else
        return false
        #endif
    }
}

/// Answers every message with why the assistant can't answer yet, and
/// where to fix it.
package struct UnavailableChatResponder: ChatResponding {
    package let reason: String

    /// What's missing, given the settings.
    package static func explaining(_ settings: AssistantSettings) -> UnavailableChatResponder {
        if let kind = settings.activeProvider {
            let configuration = settings.configuration(for: kind)
            if configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return UnavailableChatResponder(reason: L10n.tr(
                    "assistantbackendresolver.add.your.api.key.in.settings.intelligence",
                    "Add your \(String(describing: kind.displayName)) API key in Settings → Intelligence."
                ))
            }
            if !AssistantBackendResolver.remoteModelsBuilt {
                return UnavailableChatResponder(reason: L10n.tr(
                    "assistantbackendresolver.this.build.of.dayedge.can.t.use.choose.on.this.mac.in.settings.intelligence",
                    "This build of DayEdge can't use \(String(describing: kind.displayName)). Choose On this Mac in Settings → Intelligence."
                ))
            }
            return UnavailableChatResponder(reason: L10n.tr(
                "assistantbackendresolver.choose.a.model.in.settings.intelligence",
                "Choose a \(String(describing: kind.displayName)) model in Settings → Intelligence."
            ))
        }
        return UnavailableChatResponder(
            reason: "Ask DayEdge needs a language model. Turn on Apple Intelligence, or choose a provider in Settings → Intelligence."
        )
    }

    package func reply(to conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(reason)
            continuation.finish()
        }
    }
}

/// Whether Apple's on-device model can answer, and if not, why.
package enum OnDeviceModelStatus: Equatable, Sendable {
    case ready
    case turnedOff
    case unsupported
    case preparing
    case notInThisBuild

    package var title: String {
        switch self {
        case .ready: return L10n.tr("assistant.availability.ready", "Ready")
        case .turnedOff: return L10n.tr("assistantbackendresolver.turn.on.apple.intelligence.in.system.settings", "Turn on Apple Intelligence in System Settings")
        case .unsupported: return L10n.tr("assistantbackendresolver.this.mac.doesn.t.support.apple.intelligence", "This Mac doesn't support Apple Intelligence")
        case .preparing: return L10n.tr("assistantbackendresolver.getting.ready.the.model.is.downloading", "Getting ready — the model is downloading")
        case .notInThisBuild: return L10n.tr("assistantbackendresolver.not.available.in.this.build", "Not available in this build")
        }
    }
}
