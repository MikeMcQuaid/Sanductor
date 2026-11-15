import DashboardFeature
import SanductorData
import SanductorDomain
import SanductorInterface
import SwiftUI

struct WorkModeSettingsPane: View {
    // MARK: Internal

    let dashboard: DashboardModel

    var body: some View {
        Form {
            Section {
                Toggle("Hide work repositories outside working hours", isOn: $settings.isEnabled)
                if settings.isEnabled {
                    Toggle(isOn: Binding(
                        get: { (settings.snoozeUntil ?? .distantPast) > Date() },
                        set: { settings.snoozeUntil = $0 ? Date().addingTimeInterval(Self.snoozeDuration) : nil },
                    )) {
                        HStack {
                            Text("Show work repositories for 15 minutes")
                            if let until = settings.snoozeUntil, until > Date() {
                                Text("Until \(until, style: .time)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            workingHours
            holiday
            selectionSection("Organisations", choices: organisations, keyPath: \.organisations)
            selectionSection(
                "Repositories",
                choices: dashboard.workModeRepositories(selected: settings.repositories),
                keyPath: \.repositories,
            )
        }
        .formStyle(.grouped)
        .task {
            organisations = Array(dashboard.cachedOrganisations().dropFirst())
            let found = await dashboard.workModeOrganisations(selected: settings.organisations)
            organisations = found.choices
            settings.organisations = settings.organisations.filter { selected in
                found.users.contains { $0.caseInsensitiveCompare(selected) == .orderedSame } == false
            }
        }
        .task(id: settings.snoozeUntil) {
            guard let until = settings.snoozeUntil, until > Date() else {
                return
            }

            try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
            if Task.isCancelled == false {
                settings.snoozeUntil = nil
            }
        }
        .onChange(of: settings) {
            AppSettings.workMode = settings
            dashboard.refreshWorkMode()
        }
    }

    // MARK: Private

    private static let minutesPerHour = 60
    private static let avatarSize: CGFloat = 16
    // swiftlint:disable:next no_magic_numbers - The single user-facing snooze duration.
    private static let snoozeDuration: TimeInterval = 15 * 60

    @State private var settings: WorkMode = AppSettings.workMode
    @State private var organisations: [String] = []

    @ViewBuilder private var holiday: some View {
        if settings.isEnabled {
            Section {
                HStack {
                    Toggle("Holiday mode", isOn: Binding(
                        get: { (settings.holidayUntil ?? .distantPast) > Date() },
                        set: { enabled in
                            settings.holidayUntil = enabled
                                ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) : nil
                        },
                    ))
                    if (settings.holidayUntil ?? .distantPast) > Date() {
                        DatePicker(
                            "Until",
                            selection: Binding(
                                get: { settings.holidayUntil ?? Date() },
                                set: { settings.holidayUntil = $0 },
                            ),
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute],
                        )
                    }
                }
                Text("Work notifications stay silent outside working hours and during holidays. "
                    + "Scheduled work jobs run outside working hours but are skipped during holidays.")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var workingHours: some View {
        Section("Working hours") {
            HStack {
                DatePicker("From", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
            }
            HStack {
                ForEach(1 ... Calendar.current.weekdaySymbols.count, id: \.self) { day in
                    Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(
                        get: { settings.weekdays.contains(day) },
                        set: { enabled in
                            if enabled {
                                settings.weekdays.insert(day)
                            } else {
                                settings.weekdays.remove(day)
                            }
                        },
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            Text("Uses this Mac's local time zone. Overnight hours end the following day; "
                + "equal times mean all day.")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionSection(
        _ title: String, choices: [String], keyPath: WritableKeyPath<WorkMode, Set<String>>,
    ) -> some View {
        Section(title) {
            ForEach(
                settings[keyPath: keyPath].sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                id: \.self,
            ) { name in
                HStack {
                    selectionLabel(choices.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name)
                    Spacer()
                    Button("Remove " + name, systemImage: "minus.circle") {
                        selection(name, in: keyPath).wrappedValue = false
                    }
                    .labelStyle(.iconOnly)
                    .hoverHelp("Stop treating " + name + " as work")
                }
            }
            Menu("Add " + (keyPath == \.organisations ? "organisation" : "repository"), systemImage: "plus") {
                ForEach(choices.filter { selection($0, in: keyPath).wrappedValue == false }, id: \.self) { name in
                    Button { selection(name, in: keyPath).wrappedValue = true } label: { selectionLabel(name) }
                }
            }
            .disabled(choices.allSatisfy { selection($0, in: keyPath).wrappedValue })
        }
        .task(id: choices + settings[keyPath: keyPath].sorted()) {
            OwnerAvatar.preload((choices + settings[keyPath: keyPath]).compactMap { name in
                name.split(separator: "/").first.map(String.init)
            })
        }
    }

    private func selectionLabel(_ name: String) -> some View {
        Label {
            Text(name)
        } icon: {
            OwnerAvatar(owner: name.split(separator: "/").first.map(String.init), size: Self.avatarSize).menuImage
        }
        .labelStyle(.titleAndIcon)
    }

    private func selection(_ name: String, in keyPath: WritableKeyPath<WorkMode, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath].contains { $0.caseInsensitiveCompare(name) == .orderedSame } },
            set: { enabled in
                settings[keyPath: keyPath] = settings[keyPath: keyPath].filter { selected in
                    selected.caseInsensitiveCompare(name) != .orderedSame
                }
                if enabled {
                    settings[keyPath: keyPath].insert(name)
                }
            },
        )
    }

    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minute = start ? settings.startMinute : settings.endMinute
                return Calendar.current.date(
                    bySettingHour: minute / Self.minutesPerHour,
                    minute: minute % Self.minutesPerHour,
                    second: 0,
                    of: Date(),
                ) ?? Date()
            },
            set: { date in
                let minute = Calendar.current.component(.hour, from: date) * Self.minutesPerHour
                    + Calendar.current.component(.minute, from: date)
                if start {
                    settings.startMinute = minute
                } else {
                    settings.endMinute = minute
                }
            },
        )
    }
}
