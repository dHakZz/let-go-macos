import Foundation

public enum InspectionTargetKind: String, Sendable {
    case file
    case folder
    case volume
}

public struct OpenHandle: Hashable, Sendable {
    public let descriptor: String
    public let access: String?
    public let type: String?
    public let path: String

    public init(descriptor: String, access: String?, type: String?, path: String) {
        self.descriptor = descriptor
        self.access = access
        self.type = type
        self.path = path
    }
}

public struct HoldingProcess: Identifiable, Hashable, Sendable {
    public let pid: Int32
    public let command: String
    public let userID: UInt32?
    public let handles: [OpenHandle]

    public var id: Int32 { pid }

    public init(pid: Int32, command: String, userID: UInt32?, handles: [OpenHandle]) {
        self.pid = pid
        self.command = command
        self.userID = userID
        self.handles = handles
    }
}

public struct InspectionResult: Sendable {
    public let target: URL
    public let kind: InspectionTargetKind
    public let processes: [HoldingProcess]
    public let completedAt: Date

    public init(
        target: URL,
        kind: InspectionTargetKind,
        processes: [HoldingProcess],
        completedAt: Date = Date()
    ) {
        self.target = target
        self.kind = kind
        self.processes = processes
        self.completedAt = completedAt
    }
}
