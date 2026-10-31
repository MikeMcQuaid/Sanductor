/// Shared log sanitising for viewing and copying complete diagnostics.
enum CheckLog {
    /// A log line without its timestamp, byte order mark or colour.
    static func stripped(_ text: String) -> String {
        strippingANSI(text)
            .replacing(/^\x{FEFF}?[ \t]*\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z ?/, with: "")
    }

    static func strippingANSI(_ text: String) -> String {
        text.replacing(/\e\[[0-9;?]*[@-~]/, with: "")
    }
}
