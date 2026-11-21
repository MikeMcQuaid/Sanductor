import Foundation

/// Working hours and holidays for repository visibility, alerts and scheduled jobs.
public struct WorkMode: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init() {
        // Weekdays, 09:00–17:00 by default.
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        organisations = try container.decode(Set<String>.self, forKey: .organisations)
        repositories = try container.decodeIfPresent(Set<String>.self, forKey: .repositories) ?? []
        weekdays = try container.decode(Set<Int>.self, forKey: .weekdays)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        endMinute = try container.decode(Int.self, forKey: .endMinute)
        holidayUntil = try container.decodeIfPresent(Date.self, forKey: .holidayUntil)
        snoozeUntil = try container.decodeIfPresent(Date.self, forKey: .snoozeUntil)
    }

    // MARK: Public

    public var isEnabled = false
    public var organisations: Set<String> = []
    public var repositories: Set<String> = []
    public var holidayUntil: Date?
    public var snoozeUntil: Date?
    // swiftlint:disable:next no_magic_numbers - Calendar weekday numbering.
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    // swiftlint:disable:next no_magic_numbers - Default working hours.
    public var startMinute = 9 * Self.minutesPerHour
    // swiftlint:disable:next no_magic_numbers - Default working hours.
    public var endMinute = 17 * Self.minutesPerHour

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(organisations.sorted(), forKey: .organisations)
        try values.encode(repositories.sorted(), forKey: .repositories)
        try values.encode(weekdays.sorted(), forKey: .weekdays)
        try values.encode(startMinute, forKey: .startMinute)
        try values.encode(endMinute, forKey: .endMinute)
        try values.encodeIfPresent(holidayUntil, forKey: .holidayUntil)
        try values.encodeIfPresent(snoozeUntil, forKey: .snoozeUntil)
    }

    public func isWorking(at date: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: date) * Self.minutesPerHour
            + calendar.component(.minute, from: date)
        let day = calendar.component(.weekday, from: date)
        if startMinute < endMinute {
            return weekdays.contains(day) && (startMinute ..< endMinute).contains(minute)
        }
        if startMinute == endMinute {
            return weekdays.contains(day)
        }
        let previousDay = day == 1 ? calendar.weekdaySymbols.count : day - 1
        return (weekdays.contains(day) && minute >= startMinute)
            || (weekdays.contains(previousDay) && minute < endMinute)
    }

    public func hiddenOrganisations(at date: Date, calendar: Calendar = .current) -> Set<String> {
        if hidesWork(at: date, calendar: calendar) {
            Set(organisations.map { $0.lowercased() })
        } else {
            []
        }
    }

    public func hiddenRepositories(at date: Date, calendar: Calendar = .current) -> Set<String> {
        if hidesWork(at: date, calendar: calendar) {
            Set(repositories.map { $0.lowercased() })
        } else {
            []
        }
    }

    public func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else {
            return nil
        }

        let deadlines = [holidayUntil, snoozeUntil].compactMap(\.self).filter { $0 > date }
        let hours = [0, startMinute, endMinute].compactMap { minute in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: minute / Self.minutesPerHour, minute: minute % Self.minutesPerHour),
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
            )
        }
        return (deadlines + hours).min()
    }

    /// Matches both whole organisations and individual repositories, regardless of case.
    public func includes(_ repository: Repository) -> Bool {
        organisations.contains { $0.caseInsensitiveCompare(repository.owner ?? "") == .orderedSame }
            || repositories.contains { $0.caseInsensitiveCompare(repository.fullName ?? "") == .orderedSame }
    }

    public func isOnHoliday(at date: Date) -> Bool {
        isEnabled && (holidayUntil ?? .distantPast) > date
    }

    /// Snooze reveals repositories without restoring interruptions.
    public func silences(_ repository: Repository, at date: Date, calendar: Calendar = .current) -> Bool {
        isEnabled && includes(repository)
            && (isOnHoliday(at: date) || isWorking(at: date, calendar: calendar) == false)
    }

    // MARK: Private

    private enum CodingKeys: CodingKey {
        case isEnabled
        case organisations
        case repositories
        case weekdays
        case startMinute
        case endMinute
        case holidayUntil
        case snoozeUntil
    }

    private static let minutesPerHour = 60

    private func hidesWork(at date: Date, calendar: Calendar) -> Bool {
        if let snoozeUntil, date < snoozeUntil {
            return false
        }
        return isEnabled && (isOnHoliday(at: date) || isWorking(at: date, calendar: calendar) == false)
    }
}
