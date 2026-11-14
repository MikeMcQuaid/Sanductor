import Foundation
import SanductorData
import SanductorDomain

/// The sidebar the last run left behind: written on every
/// reading and painted before the first one, so the window opens
/// on its own rows and its own selection rather than on an empty
/// frame. Only what herdr owns arrives late.
extension DashboardModel {
    /// The models and efforts an agent offers, and what to start on:
    /// models the CLI reported at startup when it answered, the
    /// cached catalogue while discovery is in flight.
    public func launchChoices(for agent: AgentKind) -> AgentChoices {
        let fallback = service.launchChoices(for: agent)
        let models = discoveredModels[agent] ?? fallback.models
        let defaults = service.launchDefaults(for: agent, models: models)
        return AgentChoices(
            models: models,
            efforts: fallback.efforts,
            defaultModel: defaults.model,
            defaultEffort: defaults.effort,
            modelEfforts: modelCatalogues[agent]?.efforts ?? [:],
            modelDefaultEfforts: modelCatalogues[agent]?.defaultEfforts ?? [:],
            names: modelNames[agent] ?? [:],
            version: installedVersions[agent],
            isAvailable: availableAgents.contains(agent),
        )
    }

    func discoverModels(ifFilesChanged: Bool = false) async {
        let filesStamp = service.modelFilesStamp()
        if ifFilesChanged, modelFilesStamp == filesStamp {
            return
        }
        guard isDiscoveringModels == false else {
            return
        }

        modelFilesStamp = filesStamp
        isDiscoveringModels = true

        let known = store.load()
        await withTaskGroup(of: (AgentKind, String?, AgentModelCatalogue?).self) { tasks in
            for agent in AgentKind.allCases {
                tasks.addTask {
                    let stamp = await self.service.modelListingStamp(for: agent)
                    guard stamp == nil || stamp != known.discoveredModelsVersion[agent.rawValue]
                        || known.modelCatalogues[agent.rawValue] == nil
                    else {
                        return (agent, stamp, nil)
                    }

                    return await (agent, stamp, self.service.discoverModels(for: agent))
                }
            }
            for await (agent, stamp, catalogue) in tasks {
                if let version = stamp?.split(separator: "#").first, version.isEmpty == false {
                    installedVersions[agent] = String(version)
                }
                guard let catalogue else {
                    continue
                }

                discoveredModels[agent] = catalogue.models
                modelNames[agent] = catalogue.names
                modelCatalogues[agent] = catalogue
                store.update { metadata in
                    metadata.discoveredModels[agent.rawValue] = catalogue.models
                    metadata.discoveredModelsVersion[agent.rawValue] = stamp
                    metadata.modelCatalogues[agent.rawValue] = catalogue
                }
            }
        }
        isDiscoveringModels = false
        publishSessionChoices()
        if service.modelFilesStamp() != filesStamp {
            await discoverModels(ifFilesChanged: true)
        }
    }

    func readModelNames() {
        for agent in AgentKind.allCases {
            modelNames[agent] = service.modelNames(for: agent)
        }
    }

    func restoreDiscoveredModels() {
        let metadata = store.load()
        for agent in AgentKind.allCases {
            modelCatalogues[agent] = metadata.modelCatalogues[agent.rawValue]
            discoveredModels[agent] = metadata.modelCatalogues[agent.rawValue]?.models
        }
    }

    /// Paints the remembered sidebar, selection included.
    func restoreCachedSidebar() {
        let cached = store.load().cachedSidebar
        groups = cached.map { cached in
            let repository = Repository(name: cached.name, path: cached.path, fullName: cached.fullName)
            let items = cached.worktrees.map { worktree in
                WorktreeItem(
                    worktree: Worktree(
                        repositoryName: cached.name,
                        repositoryPath: cached.path,
                        branch: worktree.branch,
                        path: worktree.path,
                        isHostDirectory: worktree.isHostDirectory,
                    ),
                    session: nil,
                    isDirty: worktree.isDirty,
                    aheadOfUpstream: worktree.aheadOfUpstream,
                    aheadOfDefault: worktree.aheadOfDefault,
                    behindDefault: worktree.behindDefault,
                    behindUpstream: worktree.behindUpstream,
                    lastActivityAt: worktree.lastActivityAt,
                    revision: worktree.revision,
                )
            }
            return RepositoryGroup(
                repository: repository,
                items: items,
                defaultBranch: cached.defaultBranch,
                localBranches: cached.localBranches ?? [],
            )
        }
        // The stacks the last run derived come back with the rows,
        // and count as fresh for one interval: the first reading
        // otherwise derived every one of them in its first second.
        for worktree in cached.flatMap(\.worktrees) where worktree.stackCheckedOut != nil {
            derivedStacks[worktree.path] = BranchStack(
                base: worktree.stackBase,
                branches: worktree.stackBranches,
                checkedOut: worktree.stackCheckedOut ?? worktree.branch,
            )
            nextStackDerivation[worktree.path] = Date().addingTimeInterval(Self.stackInterval)
        }
        awaitedSessions = Set(
            cached.flatMap(\.worktrees).filter(\.hasSession).map(\.path),
        )
        if groups.isEmpty == false {
            hasLoaded = true
            let stored = UserDefaults.standard.string(forKey: Self.selectedWorktreeKey)
            selection = groups.flatMap(\.items).first { $0.worktree.path == stored }
            hasRestoredSelection = selection != nil
        }
    }

    func cacheSidebar(_ groups: [RepositoryGroup]) {
        // Placeholders are what a creation looks like while it runs;
        // remembering one meant a failed creation came back on every
        // launch as a row nothing could delete.
        let real = groups.map { group in
            var kept = group
            kept.items = group.items.filter { $0.isPlaceholder == false }
            return kept
        }
        let cached = real.map { group in
            var cached = CachedRepository()
            cached.name = group.repository.name
            cached.fullName = group.repository.fullName
            cached.path = group.repository.path
            cached.defaultBranch = group.defaultBranch
            cached.localBranches = group.localBranches
            cached.worktrees = group.items.map { item in
                var worktree = CachedWorktree()
                worktree.branch = item.worktree.branch
                worktree.path = item.worktree.path
                worktree.isHostDirectory = item.worktree.isHostDirectory
                worktree.isDirty = item.isDirty
                worktree.aheadOfUpstream = item.aheadOfUpstream
                worktree.aheadOfDefault = item.aheadOfDefault
                worktree.behindDefault = item.behindDefault
                worktree.behindUpstream = item.behindUpstream
                worktree.lastActivityAt = item.lastActivityAt
                worktree.revision = item.revision
                worktree.hasSession = item.session != nil
                if let stack = derivedStacks[item.worktree.path] {
                    worktree.stackBase = stack.base
                    worktree.stackBranches = stack.branches
                    worktree.stackCheckedOut = stack.checkedOut
                }
                return worktree
            }
            return cached
        }
        store.update { $0.cachedSidebar = cached }
        publishSidebar(real)
    }

    private func publishSidebar(_ real: [RepositoryGroup]) {
        let sidebar = real.map { group in
            SidebarRepository(
                name: group.repository.name,
                owner: group.repository.owner,
                worktrees: group.items.filter { $0.worktree.isHostDirectory == false }.map(\.worktree.path),
                entries: group.items.filter { $0.worktree.isHostDirectory == false }.map { item in
                    SidebarEntry(
                        target: SidebarTarget(item.worktree),
                        status: sidebarStatus(for: item),
                        activity: item.session?.activity,
                        block: block(for: item),
                    )
                },
                lastActivityAt: SessionService.repositoryActivity(of: group),
                fullName: group.repository.fullName,
                defaultBranch: group.defaultBranch,
                isHidden: isWorkHidden(group.repository),
            )
        }
        if sidebar != publishedSidebar, service.publishSidebar(sidebar) {
            publishedSidebar = sidebar
        }
    }
}
