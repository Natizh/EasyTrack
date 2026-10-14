import Foundation

enum RecurringSchedule {
    static func occurrenceID(ruleID: UUID, day: LocalDay) -> String {
        "\(ruleID.uuidString)|\(day.isoString)"
    }

    static func timeZone(for rule: RecurringRule) throws -> TimeZone {
        guard let zone = TimeZone(identifier: rule.timeZoneIdentifier) else {
            throw RecurringError.invalidSchedule
        }
        return zone
    }

    static func day(for rule: RecurringRule, index: Int) throws -> LocalDay {
        guard (0..<1_000_000).contains(index) else { throw RecurringError.invalidSchedule }
        let zone = try timeZone(for: rule)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let anchor = rule.startDay.noon(in: zone) else { throw RecurringError.invalidDate }
        let date: Date?
        switch rule.frequency {
        case .weekly:
            date = calendar.date(byAdding: .day, value: index * 7, to: anchor)
        case .monthly:
            guard let first = calendar.date(from: DateComponents(year: rule.startDay.year,
                                                                  month: rule.startDay.month, day: 1, hour: 12)),
                  let month = calendar.date(byAdding: .month, value: index, to: first),
                  let days = calendar.range(of: .day, in: .month, for: month) else {
                throw RecurringError.invalidSchedule
            }
            let parts = calendar.dateComponents([.year, .month], from: month)
            date = calendar.date(from: DateComponents(year: parts.year, month: parts.month,
                                                      day: min(rule.startDay.day, days.count), hour: 12))
        case .yearly:
            guard let first = calendar.date(from: DateComponents(year: rule.startDay.year,
                                                                  month: rule.startDay.month, day: 1, hour: 12)),
                  let year = calendar.date(byAdding: .year, value: index, to: first),
                  let days = calendar.range(of: .day, in: .month, for: year) else {
                throw RecurringError.invalidSchedule
            }
            let parts = calendar.dateComponents([.year, .month], from: year)
            date = calendar.date(from: DateComponents(year: parts.year, month: parts.month,
                                                      day: min(rule.startDay.day, days.count), hour: 12))
        }
        guard let date else { throw RecurringError.invalidSchedule }
        return LocalDay(date: date, timeZone: zone)
    }

    static func nextDay(for rule: RecurringRule) throws -> LocalDay? {
        let next = try day(for: rule, index: rule.nextIndex)
        if let end = rule.endDay, next > end { return nil }
        return next
    }

    static func due(for rule: RecurringRule, now: Date, limit: Int = 1_000) throws -> [UpcomingRecurringItem] {
        guard rule.isActive, rule.archivedAt == nil else { return [] }
        let zone = try timeZone(for: rule)
        let today = LocalDay(date: now, timeZone: zone)
        var items: [UpcomingRecurringItem] = []
        for offset in 0...limit {
            let index = rule.nextIndex + offset
            let scheduled = try day(for: rule, index: index)
            if let end = rule.endDay, scheduled > end { return items }
            if scheduled > today { return items }
            guard offset < limit else { throw RecurringError.tooManyMissed }
            items.append(UpcomingRecurringItem(rule: rule, index: index, day: scheduled))
        }
        return items
    }

    static func upcoming(for rule: RecurringRule, now: Date, days: Int = 30,
                         limit: Int = 12) throws -> [UpcomingRecurringItem] {
        guard rule.isActive, rule.archivedAt == nil, days >= 0 else { return [] }
        let zone = try timeZone(for: rule)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = LocalDay(date: now, timeZone: zone)
        guard let todayNoon = today.noon(in: zone),
              let horizonDate = calendar.date(byAdding: .day, value: days,
                                              to: todayNoon) else { throw RecurringError.invalidDate }
        let horizon = LocalDay(date: horizonDate, timeZone: zone)
        var items: [UpcomingRecurringItem] = []
        for offset in 0..<limit {
            let index = rule.nextIndex + offset
            let scheduled = try day(for: rule, index: index)
            if let end = rule.endDay, scheduled > end { break }
            if scheduled > horizon { break }
            if scheduled >= today { items.append(UpcomingRecurringItem(rule: rule, index: index, day: scheduled)) }
        }
        return items
    }
}
