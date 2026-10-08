import Foundation

/// The assistant's tools, registered in one place. Tier 1 is read-only.
package enum AssistantToolbox {
    package static func readOnly(_ context: AssistantToolContext) -> [AssistantTool] {
        [
            CurrentDateTool.make(context),
            AgendaTool.make(context),
            FreeTimeTool.make(context),
            EventSearchTool.make(context),
            EventDetailsTool.make(context),
            TaskListTool.make(context),
            TaskRecurrenceTool.make(context),
            DaysTool.make(context)
        ]
    }

    /// Tier 2: changes, each approved by the user in the chat. Only where
    /// the conversation can show the approval card.
    package static func changes(_ context: AssistantToolContext) -> [AssistantTool] {
        guard context.approvals != nil, context.changes != nil else { return [] }
        // On-device, event changes were picked wrongly about half the time
        // (create for rename, a task for "schedule lunch" — measured by
        // AppleFoundationModelsChangeLiveTests); tasks were right every time.
        let tools = context.isCompact
            ? TaskChangeTools.make(context)
            : TaskChangeTools.make(context) + EventChangeTools.make(context)
        return tools
    }
}

extension AssistantTool {
    /// A tool whose problems are answered in text rather than thrown:
    /// FoundationModels abandons the whole reply when a tool throws, while a
    /// message lets any model correct itself ("use a date like …").
    package static func answering(
        name: String,
        description: String,
        parameters: [Parameter],
        _ body: @escaping @Sendable (AssistantToolArguments) async throws -> String
    ) -> AssistantTool {
        AssistantTool(name: name, description: description, parameters: parameters) { arguments in
            do {
                return try await body(arguments)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AssistantWhen.Unrecognized {
                return "Couldn't read the date “\(error.text)”. Use \(AssistantWhen.accepted)."
            } catch let error as AssistantMoment.NeedsDay {
                return "“\(error.text)” has no day. Ask the user which day, then pass it like \(AssistantMoment.accepted)."
            } catch AssistantToolArgumentError.missing(let name) {
                return "Missing the “\(name)” argument."
            } catch {
                return "Couldn't do that: \(error.localizedDescription)"
            }
        }
    }
}
