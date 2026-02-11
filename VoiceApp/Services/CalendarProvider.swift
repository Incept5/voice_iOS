import EventKit
import Foundation

@MainActor
@Observable
final class CalendarProvider {
    var isAuthorized = false
    var todayEvents: [String] = []
    var reminders: [String] = []
    var error: String?

    private nonisolated(unsafe) let store = EKEventStore()

    func requestAccess() async {
        error = nil

        // Handle each permission separately so one failure doesn't block the other
        var eventsGranted = false
        var remindersGranted = false

        do {
            eventsGranted = try await store.requestFullAccessToEvents()
        } catch {
            print("[Calendar] Events access error: \(error)")
        }

        do {
            remindersGranted = try await store.requestFullAccessToReminders()
        } catch {
            print("[Calendar] Reminders access error: \(error)")
        }

        isAuthorized = eventsGranted || remindersGranted

        if isAuthorized {
            await fetchAll()
        } else {
            self.error = "Calendar access denied. Enable in Settings."
        }
    }

    func fetchAll() async {
        let results = await fetchOffMain()
        todayEvents = results.events
        reminders = results.reminders
    }

    // Run EKEventStore sync operations off the main actor
    private nonisolated func fetchOffMain() async -> (events: [String], reminders: [String]) {
        let events = fetchTodayEventsSync()
        let reminders = await fetchIncompleteRemindersAsync()
        return (events, reminders)
    }

    private nonisolated func fetchTodayEventsSync() -> [String] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        return events.map { event in
            let title = event.title ?? "Untitled"
            if event.isAllDay {
                return "\(title), all day"
            }
            let time = timeFormatter.string(from: event.startDate)
            return "\(title) at \(time)"
        }
    }

    private nonisolated func fetchIncompleteRemindersAsync() async -> [String] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { ekReminders in
                let result = (ekReminders ?? []).prefix(10).map { r in
                    r.title ?? "Untitled"
                }
                continuation.resume(returning: Array(result))
            }
        }
    }
}
