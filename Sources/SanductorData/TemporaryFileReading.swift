import Foundation

// MARK: - TemporaryFileReading

protocol TemporaryFileReading: Sendable {
    func attributes(_ name: String, relativeTo directory: Int32) throws -> stat?
    func names(in directory: Int32) throws -> [String]
}

// MARK: - LocalTemporaryFileReader

struct LocalTemporaryFileReader: TemporaryFileReading {
    func attributes(_ name: String, relativeTo directory: Int32) throws -> stat? {
        var attributes = stat()
        guard unsafe fstatat(directory, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT {
                return nil
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return attributes
    }

    func names(in directory: Int32) throws -> [String] {
        let descriptor = dup(directory)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard let stream = unsafe fdopendir(descriptor) else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(descriptor)
            throw error
        }

        defer { unsafe closedir(stream) }
        var names = [String]()
        while true {
            errno = 0
            guard let entry = unsafe readdir(stream) else {
                guard errno == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }

                return names
            }

            let name = unsafe withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                unsafe String(bytes: bytes.prefix(Int(entry.pointee.d_namlen)), encoding: .utf8)
            }
            if let name, name != ".", name != ".." {
                names.append(name)
            }
        }
    }
}
