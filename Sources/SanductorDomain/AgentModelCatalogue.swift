import Foundation

/// A CLI's model names and supported efforts, persisted together.
public struct AgentModelCatalogue: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        models: [String],
        names: [String: String] = [:],
        efforts: [String: [String]] = [:],
        defaultEfforts: [String: String] = [:],
    ) {
        self.names = names
        self.models = Set(models)
            .filter { model in
                model.first?.isLetter == true
                    && model.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
            }
            .sorted { left, right in
                let lhs = names[left] ?? AgentOptionName.display(left)
                let rhs = names[right] ?? AgentOptionName.display(right)
                let families = ["fable", "astra", "opus", "sol", "sonnet", "terra", "haiku", "luna"]
                let first = families.firstIndex { lhs.lowercased().contains($0) } ?? families.count
                let second = families.firstIndex { rhs.lowercased().contains($0) } ?? families.count
                return first == second ? lhs.compare(rhs, options: .numeric) == .orderedDescending : first < second
            }
        let order = ["ultra", "max", "xhigh", "high", "medium", "low", "minimal", "none"]
        self.efforts = efforts.mapValues { levels in
            levels.filter { $0.isEmpty == false && $0.allSatisfy(\.isLetter) }.sorted { left, right in
                (order.firstIndex(of: left) ?? order.count) < (order.firstIndex(of: right) ?? order.count)
            }
        }
        self.defaultEfforts = defaultEfforts
    }

    // MARK: Public

    public let models: [String]
    public let names: [String: String]
    public let efforts: [String: [String]]
    public let defaultEfforts: [String: String]

    /// Omitting both flags lets the CLI choose its own supported defaults.
    public func supports(model: String?, effort: String?) -> Bool {
        guard let model, model.isEmpty == false else {
            return effort == nil || effort?.isEmpty == true
        }
        guard models.contains(model) else {
            return false
        }

        return effort == nil || effort?.isEmpty == true || efforts[model, default: []].contains(effort ?? "")
    }
}
