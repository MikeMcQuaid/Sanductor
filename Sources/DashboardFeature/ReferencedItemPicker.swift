import AppKit
import SanductorDomain
import SwiftUI
import TerminalUI

// MARK: - ReferencedItemPicker

/// A pop-up for an open issue, pull request or security advisory
/// that searches as you type: opening it focuses a field over the
/// list, digits jump to a number and anything else matches a GHSA
/// id or a title. Arrows move the highlight, return or a click picks
/// and Escape closes it. One that `allowsSeveral` still picks one that
/// way; its rows' checkboxes, Cmd-click and Cmd-Return check several
/// while the list stays open, and a footer counts and clears them.
/// Given `lookUp`, a pause in typing also asks GitHub, for what the
/// list is too short to hold.
struct ReferencedItemPicker<Item: ReferencedItem>: View {
    // MARK: Lifecycle

    /// Creates the picker; `label` names it for assistive technology
    /// the way a picker's own label would, since the button shows
    /// only the picks.
    init(
        _ label: String,
        selection: Binding<Set<Item.ID>>,
        allowsSeveral: Bool,
        items: [Item],
        placeholder: String,
        searchPrompt: String,
        loadingTitle: String,
        emptyTitle: String,
        isLoading: Bool,
        lookUp: (@MainActor (String) async -> [Item])? = nil,
    ) {
        self.label = label
        _selection = selection
        self.allowsSeveral = allowsSeveral
        self.items = items
        self.placeholder = placeholder
        self.searchPrompt = searchPrompt
        self.loadingTitle = loadingTitle
        self.emptyTitle = emptyTitle
        self.isLoading = isLoading
        self.lookUp = lookUp
    }

    // MARK: Internal

    @Binding var selection: Set<Item.ID>

    let label: String
    let allowsSeveral: Bool
    let items: [Item]
    let placeholder: String
    let searchPrompt: String
    let loadingTitle: String
    let emptyTitle: String
    let isLoading: Bool
    let lookUp: (@MainActor (String) async -> [Item])?

    var body: some View {
        let listed = Set(items.map(\.id))
        let picked = (items + found.filter { listed.contains($0.id) == false }).filter { selection.contains($0.id) }
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(picked.first.map { $0.reference + " " + $0.title } ?? placeholder)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // Outside the title, so a long one never truncates
                // the count away.
                if picked.count > 1 {
                    Text("+" + String(picked.count - 1))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(label)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { search }
    }

    // MARK: Private

    @State private var isPresented = false
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool
    /// GitHub's answer for `lookedUpQuery`, shown only while that is
    /// still the query.
    @State private var lookedUp: [Item] = []
    @State private var lookedUpQuery = ""
    /// Everything a lookup has answered, so a pick from one still
    /// names itself on the button once the search has moved on.
    @State private var found: [Item] = []
    @State private var isLookingUp = false

    /// Ranked once per render, since the body reads it several times:
    /// the list's own matches, then GitHub's that are not among them.
    private var results: [Item] {
        let local = ReferencedItemSearch.rank(items, query: query)
        let shown = Set(local.map(\.id))
        return lookedUpQuery == query ? local + lookedUp.filter { shown.contains($0.id) == false } : local
    }

    /// Whether the query asks for more than the list holds: any text,
    /// or a number with no exact match in it.
    private var needsLookUp: Bool {
        guard lookUp != nil, ReferencedItemSearch.searched(query).isEmpty == false else {
            return false
        }
        guard let number = ReferencedItemSearch.number(in: query) else {
            return true
        }

        return items.contains { $0.reference == "#" + String(number) } == false
    }

    private var search: some View {
        let ranked = results
        return ScrollViewReader { proxy in
            PopoverContent(width: Layout.width) {
                VStack(alignment: .leading, spacing: Layout.spacing) {
                    TextField(searchPrompt, text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onChange(of: query) { highlighted = 0 }
                        .onSubmit { pick(ranked, at: highlighted) }
                        .onKeyPress(.return, phases: .down) { press in check(ranked, at: highlighted, on: press) }
                        .highlightNavigation($highlighted, count: ranked.count)
                    if ranked.isEmpty {
                        noResults
                    } else {
                        resultsList(ranked)
                        if isLookingUp {
                            lookingUpForMore
                        }
                    }
                    if allowsSeveral, items.isEmpty == false {
                        Divider()
                        footer(ranked)
                    }
                }
                .padding(Layout.spacing)
            }
            .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
        .onExitCommand { isPresented = false }
        .onAppear {
            highlighted = ranked.firstIndex { selection.contains($0.id) } ?? 0
            fieldFocused = true
        }
        .task(id: query) { await lookUpQuery() }
        // Clearing on close rather than open: the query's onChange
        // would otherwise reset the highlight just set to the pick.
        .onDisappear {
            query = ""
            isLookingUp = false
        }
    }

    /// Nothing to list yet, or proven to be nothing: an empty state
    /// waits for the listing and for GitHub's answer.
    private var noResults: some View {
        Group {
            if items.isEmpty, isLoading {
                ProgressView(loadingTitle)
            } else if isLookingUp {
                ProgressView("Searching GitHub…")
            } else {
                Text(items.isEmpty ? emptyTitle : "Nothing matches")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lookingUpForMore: some View {
        HStack(spacing: Layout.spacing) {
            ProgressView().controlSize(.small)
            Text("Searching GitHub for more…")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultsList(_ results: [Item]) -> some View {
        HighlightedResultsList(
            results,
            id: \.id,
            highlighted: highlighted,
            help: allowsSeveral
                ? "Return or a click picks just this one; its checkbox, Cmd-click or Cmd-Return checks several"
                : "Arrows move the highlight; return or a click picks",
            scrolls: false,
            onPick: { pick($0) },
            row: { row($0) },
        )
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: Layout.spacing) {
            if allowsSeveral {
                Toggle(isOn: isChecked(item)) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Include " + item.reference)
            }
            Text(item.reference)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 0)
            if allowsSeveral == false, selection.contains(item.id) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Chosen")
            }
        }
        .padding(.horizontal, Layout.spacing)
        .padding(.vertical, Layout.rowPadding)
    }

    /// The count and bulk actions under a list that checks several,
    /// always shown so the popover never changes height as the first
    /// box is checked, and saying how before anything is.
    private func footer(_ ranked: [Item]) -> some View {
        let unchecked = ranked.filter { selection.contains($0.id) == false }
        return HStack(spacing: Layout.spacing) {
            Text(selection.isEmpty ? "Check several to start one session each" : String(selection.count) + " checked")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if query.isEmpty == false, unchecked.isEmpty == false {
                Button("Check all " + String(unchecked.count)) { selection.formUnion(unchecked.map(\.id)) }
                    .hoverHelp("Check every result matching the search")
            }
            Button("Clear") { selection = [] }
                .disabled(selection.isEmpty)
                .hoverHelp("Uncheck everything")
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    /// Asks GitHub once typing pauses; a keystroke before the answer
    /// cancels this and starts the next. The spinner shows from the
    /// first keystroke, so "Nothing matches" waits for the answer.
    private func lookUpQuery() async {
        guard let lookUp, needsLookUp else {
            isLookingUp = false
            return
        }

        isLookingUp = true
        try? await Task.sleep(for: Layout.typingPause)
        guard Task.isCancelled == false else {
            return
        }

        let asked = query
        let answer = await lookUp(asked)
        guard Task.isCancelled == false else {
            return
        }

        let known = Set(found.map(\.id))
        found += answer.filter { known.contains($0.id) == false }
        lookedUp = answer
        lookedUpQuery = asked
        isLookingUp = false
    }

    private func isChecked(_ item: Item) -> Binding<Bool> {
        Binding(
            get: { selection.contains(item.id) },
            set: { isOn in
                if isOn {
                    selection.insert(item.id)
                } else {
                    selection.remove(item.id)
                }
            },
        )
    }

    private func pick(_ results: [Item], at index: Int) {
        if results.indices.contains(index) {
            pick(results[index])
        }
    }

    /// Picks just this one and closes, or with Cmd held checks it
    /// beside the rest, the way Cmd-click adds to a selection
    /// everywhere else on the Mac.
    private func pick(_ item: Item) {
        if allowsSeveral, NSEvent.modifierFlags.contains(.command) {
            isChecked(item).wrappedValue.toggle()
        } else {
            selection = [item.id]
            isPresented = false
        }
    }

    private func check(_ results: [Item], at index: Int, on press: KeyPress) -> KeyPress.Result {
        guard allowsSeveral, press.modifiers.contains(.command), results.indices.contains(index) else {
            return .ignored
        }

        isChecked(results[index]).wrappedValue.toggle()
        return .handled
    }
}

// MARK: - Layout

/// The picker's measurements, outside it because generic types
/// cannot hold static stored properties.
private enum Layout {
    static let spacing: CGFloat = 8
    static let rowPadding: CGFloat = 4
    static let width: CGFloat = 420
    /// How long typing rests before GitHub is asked, so a word typed
    /// quickly is one search rather than one per letter.
    static let typingPauseMilliseconds = 400
    static let typingPause: Duration = .milliseconds(typingPauseMilliseconds)
}
