import Foundation

/// One row of the Ask transcript. The conversation is flattened into small
/// rows — a bubble, a paragraph, a day's card, one event — so a lazy list
/// builds only what's on screen, however long the conversation and however
/// big an answer is.
package struct ChatTranscriptRow: Identifiable, Equatable {
    package enum Kind: Equatable {
        case user(String)
        /// A change made while answering, above the answer.
        case receipt(ChatChangeReceipt)
        /// The reply isn't written yet: the approval card (latest only, when
        /// one waits) or "thinking".
        case pending(isLatest: Bool)
        case prose(String)
        /// The card above a day's events and tasks.
        case dayHeader(ChatDayReference)
        case object(ChatContentPart)
        /// Days on their own (holidays, free days, a span).
        case dates([ChatDayReference])
    }

    /// Stable while the text grows ("<message>/b0" stays the first block),
    /// so rows keep their identity while an answer streams.
    package let id: String
    package let kind: Kind
    /// Space above the row — a lazy list has one spacing for everything,
    /// so each row carries the gap the old nested stacks had.
    package let topGap: CGFloat
}

/// The gaps between rows, from the chat theme.
package struct ChatTranscriptGaps: Equatable {
    /// Between messages.
    package var message: CGFloat
    /// Between the parts of an answer (receipts, paragraphs, days).
    package var part: CGFloat
    /// Between a day's card and its first row.
    package var dayToRows: CGFloat
}

package enum ChatTranscriptRows {
    /// The order messages are shown in: newest first — an answer above
    /// the question it answers. Inside a message the parts keep reading
    /// order.
    package static func newestFirst(_ messages: [ChatMessage]) -> [Int] {
        Array(messages.indices.reversed())
    }

    package static func rows(for message: ChatMessage, isLatest: Bool, isFirst: Bool,
                             gaps: ChatTranscriptGaps, calendar: Calendar) -> [ChatTranscriptRow] {
        let base = message.id.uuidString
        var rows: [ChatTranscriptRow] = []
        /// The first row of a message is spaced from the one before; the
        /// rest of its parts from each other.
        func gap(_ inside: CGFloat) -> CGFloat {
            rows.isEmpty ? (isFirst ? 0 : gaps.message) : inside
        }
        func add(_ id: String, _ kind: ChatTranscriptRow.Kind, inside: CGFloat) {
            rows.append(ChatTranscriptRow(id: id, kind: kind, topGap: gap(inside)))
        }

        switch message.role {
        case .user:
            add("\(base)/user", .user(message.text), inside: 0)
        case .assistant:
            for receipt in message.changes {
                add("\(base)/receipt/\(receipt.id)", .receipt(receipt), inside: gaps.part)
            }
            if message.isPending {
                add("\(base)/pending", .pending(isLatest: isLatest), inside: gaps.part)
                return rows
            }
            for (index, block) in ChatContentBlock.blocks(message.parts, calendar: calendar).enumerated() {
                let id = "\(base)/b\(index)"
                switch block {
                case .prose(let text):
                    add(id, .prose(text), inside: gaps.part)
                case .dates(let days):
                    add(id, .dates(days), inside: gaps.part)
                case .objects(let day, let parts):
                    add("\(id)/day", .dayHeader(day), inside: gaps.part)
                    for (row, part) in parts.enumerated() {
                        add("\(id)/\(row)", .object(part), inside: row == 0 ? gaps.dayToRows : 0)
                    }
                }
            }
        }
        return rows
    }
}

/// Rows per message, kept: a finished message is expanded once; while an
/// answer streams only it is rebuilt. Values only — never views. Rows come
/// out newest message first (`ChatTranscriptRows.newestFirst`).
@MainActor
package final class ChatTranscriptRowCache {
    private struct Entry {
        let message: ChatMessage
        let isLatest: Bool
        let isFirst: Bool
        let rows: [ChatTranscriptRow]
    }

    private var entries: [UUID: Entry] = [:]
    /// Messages expanded so far (tests).
    package private(set) var builds = 0

    package func rows(for messages: [ChatMessage], gaps: ChatTranscriptGaps, calendar: Calendar) -> [ChatTranscriptRow] {
        var next: [UUID: Entry] = [:]
        var rows: [ChatTranscriptRow] = []
        let order = ChatTranscriptRows.newestFirst(messages)
        for index in order {
            let message = messages[index]
            let isLatest = index == messages.count - 1
            // First on screen: no gap above it.
            let isFirst = index == order.first
            let entry: Entry
            if let cached = entries[message.id], cached.isLatest == isLatest, cached.isFirst == isFirst,
               cached.message == message {
                entry = cached
            } else {
                builds += 1
                entry = Entry(message: message, isLatest: isLatest, isFirst: isFirst,
                              rows: ChatTranscriptRows.rows(for: message, isLatest: isLatest, isFirst: isFirst,
                                                            gaps: gaps, calendar: calendar))
            }
            next[message.id] = entry
            rows += entry.rows
        }
        entries = next
        return rows
    }
}
