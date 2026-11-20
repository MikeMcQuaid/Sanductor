import Foundation

/// JSON records may span SSH packets; frame sizes are bounded before decoding.
public struct RemoteLines: Sendable {
    // MARK: Lifecycle

    /// Starts with no buffered bytes.
    public init() {
        skippingRecordsOver = nil
    }

    init(skippingRecordsOver limit: Int, skippingFirst: Bool) {
        skippingRecordsOver = limit
        discarding = skippingFirst
    }

    // MARK: Public

    /// Returns complete UTF-8 records, retaining any partial final line.
    public mutating func append(_ data: Data) throws -> [String] {
        var lines = [String]()
        var bytes = data[...]
        while bytes.isEmpty == false {
            let endOfLine = bytes.firstIndex(of: Self.newline)
            let fragment = bytes[..<(endOfLine ?? bytes.endIndex)]
            if pending.count + fragment.count > (skippingRecordsOver ?? Self.maximumRecordBytes) {
                guard skippingRecordsOver != nil else {
                    throw RemoteError("The remote record is too large.")
                }

                discarding = true
            }
            if discarding == false {
                pending.append(fragment)
            }
            guard let endOfLine else {
                break
            }

            if discarding == false {
                guard let line = String(data: pending, encoding: .utf8) else {
                    throw RemoteError("The remote record is not UTF-8.")
                }

                lines.append(line)
            }
            pending.removeAll(keepingCapacity: true)
            discarding = false
            bytes = bytes[bytes.index(after: endOfLine)...]
        }
        return lines
    }

    // MARK: Private

    private static let maximumRecordBytes = 8_388_608
    private static let newline: UInt8 = 10

    private let skippingRecordsOver: Int?
    private var discarding = false
    private var pending: Data = .init()
}
