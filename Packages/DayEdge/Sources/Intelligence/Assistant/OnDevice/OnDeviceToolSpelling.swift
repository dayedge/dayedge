import Foundation

/// The tools as the on-device model reads them: the same tools, names and
/// parameters, with short descriptions — the definitions were over half its
/// 4K window, nearly all of it descriptions (the same long "when" sentence in
/// six tools). Plain words, never abbreviations: the small model leans on
/// them. Remote models keep the full wording.
package enum OnDeviceToolSpelling {
    package struct Spelling {
        let description: String
        /// Parameter → its short description; "" when the name says it.
        let parameters: [String: String]
    }

    private static let when = "Day or period, e.g. today, next week, 2026-10-02."

    package static let table: [String: Spelling] = [
        "get_current_date": Spelling(description: "Today's date and time.", parameters: [:]),
        "get_agenda": Spelling(description: "Events and tasks of a day or period.",
                               parameters: ["when": when + " Default today."]),
        "find_free_time": Spelling(description: "Free time between events, in working hours.",
                                   parameters: ["when": when + " Default today.", "minutes": "Shortest slot, default 30."]),
        "find_events": Spelling(description: "Search events and tasks.", parameters: [
            "text": "Words anywhere.", "subject": "Words in the title.", "from": "Organizer; 'me' for the user.",
            "with": "A person taking part.", "type": "", "when": when + " Any time if left out."
        ]),
        "event_details": Spelling(description: "One event in full: people, responses, place, notes.",
                                  parameters: ["event": "Its title.", "when": "Where to look, e.g. tomorrow."]),
        "list_tasks": Spelling(description: "The user's tasks.", parameters: ["filter": "Default open.", "list": "A list's name."]),
        "task_recurrence": Spelling(description: "How a repeating task repeats, and its dates.",
                                    parameters: ["task": "Its title.", "when": "Which dates, e.g. next month."]),
        "get_days": Spelling(description: "Holidays, weekends and workdays.", parameters: ["when": when + " Default next 30 days."]),
        "create_task": Spelling(description: "Create a task.", parameters: ["title": "", "due": "e.g. tomorrow 10:00"]),
        "complete_task": Spelling(description: "Mark a task done.", parameters: ["task": "Its title."]),
        "update_task": Spelling(description: "Change a task's due date or title.",
                                parameters: ["task": "Its title.", "due": "New day and time.", "title": "New title."]),
        "delete_task": Spelling(description: "Delete a task.", parameters: ["task": "Its title."])
    ]

    /// The tool with its short descriptions (as it is, if it has none).
    package static func apply(to tool: AssistantTool) -> AssistantTool {
        guard let spelling = table[tool.name] else { return tool }
        let parameters = tool.parameters.map { parameter in
            var short = parameter
            short.description = spelling.parameters[parameter.name] ?? parameter.description
            return short
        }
        return AssistantTool(name: tool.name, description: spelling.description, parameters: parameters, call: tool.call)
    }
}
