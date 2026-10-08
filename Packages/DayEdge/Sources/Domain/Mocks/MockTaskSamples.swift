import Foundation

/// The mock's sample reminders, dated relative to `now`, built group by
/// group: needs attention and work, personal, home and groceries, completed.
struct MockTaskSamples {
    static let lists: [CalendarSource] = {
        let work = list("work", "Work", RGBAColor(red: 0.0, green: 0.478, blue: 1.0))
        let personal = list("personal", "Personal", RGBAColor(red: 0.204, green: 0.78, blue: 0.349))
        let home = list("home", "Home", RGBAColor(red: 0.686, green: 0.322, blue: 0.871))
        let groceries = list("groceries", "Groceries", RGBAColor(red: 1.0, green: 0.584, blue: 0.0), source: ("exchange-team", "Exchange", .exchange))
        return [work, personal, home, groceries]
    }()

    private static func list(_ id: String, _ title: String, _ color: RGBAColor,
                             // swiftlint:disable:next large_tuple - a default account for the samples
                             source: (id: String, title: String, kind: SourceKind) = ("icloud-reminders", "iCloud Reminders", .iCloud)) -> CalendarSource {
        CalendarSource(id: id, title: title, tint: color,
                       sourceTitle: source.title, sourceID: source.id, sourceKind: source.kind)
    }

    private let today: Date
    private let calendar: Calendar
    private var tasks: [TaskItem] = []

    static func make(now: Date, calendar: Calendar) -> [TaskItem] {
        var samples = MockTaskSamples(today: calendar.startOfDay(for: now), calendar: calendar)
        samples.addAttentionAndWork()
        samples.addPersonalHomeAndGroceries()
        samples.addCompleted()
        samples.setSourceOrder()
        return samples.tasks
    }

    private init(today: Date, calendar: Calendar) {
        self.today = today
        self.calendar = calendar
    }

    private func day(_ offset: Int, hour: Int? = nil) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        guard let hour else { return base }
        return calendar.date(byAdding: .hour, value: hour, to: base) ?? base
    }

    private mutating func add(_ title: String, _ list: String, due: Date? = nil, time: Bool = false,
                              priority: TaskPriority = .none, notes: String? = nil,
                              recurring: TaskRecurrence = .never, alert: TaskAlert? = nil) {
        tasks.append(TaskItem(
            id: "task-\(tasks.count + 1)", title: title, notes: notes, listID: list,
            dueDate: due, hasDueTime: time, priority: priority,
            recurrence: recurring, alert: alert
        ))
    }

    private mutating func addAttentionAndWork() {
        // Needs attention: overdue, today, high priority
        add("Send invoice to client", "work", due: day(-2), priority: .high, notes: "Include the September hours.")
        add("Reply to legal about the contract", "work", due: day(-1, hour: 16), time: true)
        add("Call the bank", "personal", due: day(0, hour: 14), time: true, alert: .relative(minutesBefore: 15))
        add("Submit expense report", "work", due: day(0, hour: 17), time: true, priority: .high,
            notes: "Attach receipts from September travel.\nSend after finance review.", recurring: .monthly)
        add("Book dentist", "personal", priority: .high)
        // Work
        add("Finish architecture doc", "work", due: day(1, hour: 14), time: true, priority: .medium)
        add("Review pull requests", "work", due: day(2))
        add("Prepare sprint demo", "work", due: day(4, hour: 10), time: true)
        add("Update onboarding checklist", "work", due: day(6))
        add("Plan Q4 roadmap", "work", due: day(14))
        add("Write postmortem", "work", due: day(21), notes: "Incident from last week.")
        add("Renew SSL certificates", "work", due: day(30), recurring: .monthly)
        add("Clean up old branches", "work")
        add("Read the design system RFC", "work")
        // A long Work backlog, to exercise drill-in and virtualized scrolling.
        for index in 1...60 {
            add("Backlog item \(index)", "work",
                due: index % 3 == 0 ? day(index + 3) : nil,
                priority: index % 11 == 0 ? .medium : .none)
        }
    }

    private mutating func addPersonalHomeAndGroceries() {
        // Personal
        add("Renew passport", "personal", due: day(3))
        add("Buy birthday gift", "personal", due: day(5))
        add("Plan weekend trip", "personal", due: day(9))
        add("Book flights", "personal", due: day(18))
        add("Call mum", "personal", due: day(1), recurring: .weekly)
        add("Learn a new recipe", "personal")
        // Home
        add("Fix the leaking tap", "home", due: day(2))
        add("Change air filter", "home", due: day(10), recurring: .custom("Every 3 months"))
        add("Repaint the hallway", "home", due: day(25))
        add("Order new curtains", "home")
        add("Sort the garage", "home")
        // Groceries
        add("Milk", "groceries", due: day(0))
        add("Eggs", "groceries")
        add("Coffee beans", "groceries", due: day(1))
        add("Olive oil", "groceries")
        add("Fresh basil", "groceries")
        add("Sparkling water", "groceries", due: day(3))
    }

    private mutating func addCompleted() {
        // Completed
        for (index, title) in ["Pay electricity bill", "Send meeting notes", "Book train tickets", "Update CV"].enumerated() {
            var item = TaskItem(
                id: "task-\(tasks.count + 1)", title: title, listID: index % 2 == 0 ? "personal" : "work",
                isCompleted: true, completionDate: day(-index - 1, hour: 11)
            )
            item.dueDate = day(-index - 1)
            tasks.append(item)
        }
        // A long completed history, to exercise batching.
        for index in 0..<40 {
            var item = TaskItem(
                id: "task-\(tasks.count + 1)", title: "Done: chore \(index + 1)",
                listID: ["work", "personal", "home", "groceries"][index % 4],
                isCompleted: true, completionDate: day(-(index / 2) - 5, hour: 9 + index % 8)
            )
            item.dueDate = item.completionDate
            tasks.append(item)
        }
    }

    /// Source order and (most) creation dates, as Reminders would give.
    private mutating func setSourceOrder() {
        for index in tasks.indices {
            tasks[index].sourceOrder = index
            if index % 7 != 3 { tasks[index].creationDate = day(-60 + (index * 13) % 55, hour: 9) }
        }
    }
}
