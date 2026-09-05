import Foundation
import Testing
@testable import LetGoCore

@Suite("Lock scanner")
struct LockScannerTests {
    @Test("Parses lsof field output and groups handles by process")
    func parsesLsofOutput() throws {
        let fields = [
            "p321", "cPreview", "u501", "\nf12", "ar", "tREG", "n/tmp/report.pdf",
            "\nf13", "aw", "tREG", "n/tmp/report.notes",
            "\np88", "cmds", "u0", "\nf7", "ar", "tDIR", "n/Volumes/Work"
        ]
        let bytes = fields.joined(separator: "\0").data(using: .utf8)!

        let processes = LockScanner.parse(bytes)

        #expect(processes.count == 2)
        #expect(processes[0].pid == 321)
        #expect(processes[0].command == "Preview")
        #expect(processes[0].handles.count == 2)
        #expect(processes[0].handles[1].access == "w")
        #expect(processes[1].userID == 0)
    }

    @Test("Finds a separate process holding an exact file open")
    func findsLiveOpenFile() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LetGoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appendingPathComponent("held-open.txt")
        try Data("test".utf8).write(to: file)

        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/bin/sh")
        holder.arguments = ["-c", "exec 3<\"$1\"; sleep 8", "holder", file.path]
        try holder.run()
        defer {
            if holder.isRunning { holder.terminate() }
        }

        try await Task.sleep(for: .milliseconds(250))
        let result = try await LockScanner().scan(url: file)

        #expect(result.kind == .file)
        #expect(result.processes.contains { $0.pid == holder.processIdentifier })
        #expect(result.processes.flatMap(\.handles).contains {
            URL(fileURLWithPath: $0.path).lastPathComponent == file.lastPathComponent
        })
    }
}
