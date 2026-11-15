import Foundation
import SanductorData
import SanductorDomain

public extension DashboardModel {
    /// Repositories visible during the current working hours.
    var visibleGroups: [RepositoryGroup] {
        groups.filter { isWorkHidden($0.repository) == false }
    }

    /// Whether the current visibility rules hide this repository.
    func isWorkHidden(_ repository: Repository) -> Bool {
        hiddenOrganisations.contains(repository.owner?.lowercased() ?? "")
            || hiddenRepositories.contains(repository.fullName?.lowercased() ?? "")
    }

    /// Individual repository choices, retaining saved selections.
    func workModeRepositories(selected: Set<String>) -> [String] {
        let names = groups.compactMap(\.repository.fullName) + selected.sorted()
        return Dictionary(names.map { ($0.lowercased(), $0) }) { first, _ in first }
            .values
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Includes selected organisations outside memberships and identifies saved user accounts.
    func workModeOrganisations(selected: Set<String>) async -> (choices: [String], users: Set<String>) {
        let owners = await organisations()
        var choices = Array(owners.dropFirst())
        var users = Set(owners.prefix(1))
        for owner in selected where owners.contains(where: { known in
            known.caseInsensitiveCompare(owner) == .orderedSame
        }) == false {
            guard let isOrganisation = try? await service.isOrganisation(owner: owner) else {
                continue
            }

            if isOrganisation {
                choices.append(owner)
            } else {
                users.insert(owner)
            }
        }
        return (choices.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, users)
    }

    /// Rechecks visibility and schedules the next local-time boundary.
    func refreshWorkMode(onlyIfSettingsChanged: Bool = false) {
        let settings = AppSettings.workMode
        guard onlyIfSettingsChanged == false || workModeSettings != settings else {
            return
        }

        workModeSettings = settings
        updateDockBadge(for: groups)
        let hidden = settings.hiddenOrganisations(at: Date())
        let repositories = settings.hiddenRepositories(at: Date())
        if hiddenOrganisations != hidden || hiddenRepositories != repositories {
            hiddenOrganisations = hidden
            hiddenRepositories = repositories
            cacheSidebar(groups)
        }
        if let selection, let group = groups.group(holding: selection), isWorkHidden(group.repository) {
            self.selection = nil
            showsNewSession = false
        }
        if let newSessionRepository, isWorkHidden(newSessionRepository) {
            self.newSessionRepository = nil
            showsNewSession = false
        }
        workModeTimer?.invalidate()
        workModeTimer = nil
        guard let next = settings.nextBoundary(after: Date()) else {
            return
        }

        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWorkMode()
            }
        }
        workModeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
