import Foundation

public enum LockScannerError: LocalizedError, Sendable {
    case targetMissing(String)
    case launchFailed(String)
    case scanFailed(String)

    public var errorDescription: String? {
        switch self {
        case .targetMissing(let path):
            return "The selected item no longer exists: \(path)"
        case .launchFailed(let detail):
            return "The inspection tool could not start. \(detail)"
        case .scanFailed(let detail):
            return detail.isEmpty
                ? "The inspection could not be completed."
                : "The inspection could not be completed. \(detail)"
        }
    }
}

public struct LockScanner: Sendable {
    public init() {}

    public func scan(url: URL, excludingPID: Int32 = ProcessInfo.processInfo.processIdentifier) async throws -> InspectionResult {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL

        return try await Task.detached(priority: .userInitiated) {
            try Self.scanSynchronously(url: resolvedURL, excludingPID: excludingPID)
        }.value
    }

    private static func scanSynchronously(url: URL, excludingPID: Int32) throws -> InspectionResult {
        let path = url.path
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw LockScannerError.targetMissing(path)
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isVolumeKey])
        let kind: InspectionTargetKind
        if resourceValues?.isVolume == true {
            kind = .volume
        } else if isDirectory.boolValue {
            kind = .folder
        } else {
            kind = .file
        }

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.standardOutput = standardOutput
        process.standardError = standardError

        var arguments = ["-n", "-P", "-w", "-F0pcuftan"]
        switch kind {
        case .file:
            arguments += ["--", path]
        case .folder:
            arguments += ["+D", path]
        case .volume:
            arguments += ["+f", "--", path]
        }
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            throw LockScannerError.launchFailed(error.localizedDescription)
        }

        // Reading before waiting also drains large result sets instead of letting
        // the child process block on a full pipe.
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // lsof uses exit status 1 when no matching open files are found.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            let detail = String(decoding: errorOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LockScannerError.scanFailed(detail)
        }

        let parsed = parse(output)
            .filter { $0.pid != excludingPID }
            .sorted { lhs, rhs in
                if lhs.userID == rhs.userID {
                    return lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
                }
                return lhs.userID != 0 && rhs.userID == 0
            }

        return InspectionResult(target: url, kind: kind, processes: parsed)
    }

    public static func parse(_ data: Data) -> [HoldingProcess] {
        struct FileBuilder {
            var descriptor = ""
            var access: String?
            var type: String?
            var path: String?

            var value: OpenHandle? {
                guard let path, !descriptor.isEmpty else { return nil }
                return OpenHandle(descriptor: descriptor, access: access, type: type, path: path)
            }
        }

        struct ProcessBuilder {
            var pid: Int32?
            var command = "Unknown process"
            var userID: UInt32?
            var handles: [OpenHandle] = []

            var value: HoldingProcess? {
                guard let pid else { return nil }
                return HoldingProcess(pid: pid, command: command, userID: userID, handles: handles)
            }
        }

        var results: [HoldingProcess] = []
        var currentProcess: ProcessBuilder?
        var currentFile: FileBuilder?

        func finishFile() {
            guard let file = currentFile?.value else {
                currentFile = nil
                return
            }
            currentProcess?.handles.append(file)
            currentFile = nil
        }

        func finishProcess() {
            finishFile()
            if let process = currentProcess?.value {
                results.append(process)
            }
            currentProcess = nil
        }

        for rawField in data.split(separator: 0, omittingEmptySubsequences: true) {
            let field = String(decoding: rawField, as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            guard let code = field.first else { continue }
            let value = String(field.dropFirst())

            switch code {
            case "p":
                finishProcess()
                currentProcess = ProcessBuilder(pid: Int32(value))
            case "c":
                currentProcess?.command = value
            case "u":
                currentProcess?.userID = UInt32(value)
            case "f":
                finishFile()
                currentFile = FileBuilder(descriptor: value)
            case "a":
                currentFile?.access = value.trimmingCharacters(in: .whitespaces)
            case "t":
                currentFile?.type = value
            case "n":
                currentFile?.path = value
            default:
                break
            }
        }

        finishProcess()
        return results.filter { !$0.handles.isEmpty }
    }
}
