import Foundation

/// A conversation can outlive its day: asked yesterday afternoon, continued
/// this morning. Earlier turns say "today" and "tomorrow" about *their*
/// day, and a model reading them carries that day over. So the history the
/// model sees marks each day change on the first user turn of the new day.
/// Only the model's copy is marked; the transcript on screen is unchanged.
package enum ChatTimeline {
    package static func dated(_ messages: [ChatMessage], calendar: Calendar) -> [ChatMessage] {
        var previousDay: Date?
        return messages.map { message in
            let day = calendar.startOfDay(for: message.sentAt)
            defer { previousDay = day }
            guard message.role == .user, let previousDay, previousDay != day else { return message }
            var marked = message
            marked.text = note(now: message.sentAt, earlier: previousDay, calendar: calendar) + "\n\n" + message.text
            return marked
        }
    }

    package static func note(now: Date, earlier: Date, calendar: Calendar) -> String {
        "[It is now \(AssistantInstructions.longDate(now, calendar: calendar)). The messages above were written on " +
        "\(AssistantInstructions.longDate(earlier, calendar: calendar)); “today”, “tomorrow” and dates there are " +
        "relative to that day, not to now.]"
    }
}
