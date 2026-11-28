import SwiftTerm
import SwiftUI

// MARK: - AgentOutputLink

public enum AgentOutputLink: Equatable {
    case destination(URL)
    case label(String, externalBrowser: Bool)
}

public extension EnvironmentValues {
    /// The link selected in the visible agent session.
    @Entry var agentOutputLink: Binding<AgentOutputLink?>?
}

extension PaneTerminalView {
    /// Match SwiftTerm's drag threshold, including a drag into the next cell.
    func isClick(_ event: NSEvent, from press: NSEvent) -> Bool {
        let start = convert(press.locationInWindow, from: nil)
        let end = convert(event.locationInWindow, from: nil)
        let cell = Self.cellSize(of: self)
        guard cell.width > 0, cell.height > 0 else {
            return false
        }

        // SwiftTerm uses half a cell with a three-point minimum.
        // swiftlint:disable:next no_magic_numbers
        let threshold = max(3, min(cell.width, cell.height) / 2)
        return hypot(end.x - start.x, end.y - start.y) < threshold
            && gridPosition(at: start, cell: cell) == gridPosition(at: end, cell: cell)
    }

    /// Read the styled cells only when the user clicks a label without a target.
    func underlinedLabel(at point: NSPoint) -> String? {
        let cell = Self.cellSize(of: self)
        guard bounds.contains(point), cell.width > 0, cell.height > 0 else {
            return nil
        }

        let (row, column) = gridPosition(at: point, cell: cell)
        guard let rows = terminalContentSnapshot(region: .viewport)?.rows, rows.indices.contains(row),
              rows[row].cells.indices.contains(column), rows[row].cells[column].attribute.style.contains(.underline)
        else {
            return nil
        }

        let first = rows[...row].lastIndex { $0.isWrapped == false } ?? rows.startIndex
        let limit = rows.dropFirst(row + 1).firstIndex { $0.isWrapped == false } ?? rows.endIndex
        let cells = rows[first ..< limit].flatMap(\.cells)
        let index = rows[first ..< row].reduce(column) { $0 + $1.cells.count }
        let start = cells[..<index].lastIndex { $0.attribute.style.contains(.underline) == false }.map { $0 + 1 } ?? 0
        let end = cells[index...].firstIndex { $0.attribute.style.contains(.underline) == false } ?? cells.endIndex
        return cells[start ..< end].filter { $0.width > 0 }.map { $0.isBlank ? " " : $0.text }.joined()
    }

    private func gridPosition(at point: NSPoint, cell: CGSize) -> (row: Int, column: Int) {
        (Int(floor((bounds.height - point.y) / cell.height)), Int(floor(point.x / cell.width)))
    }
}
