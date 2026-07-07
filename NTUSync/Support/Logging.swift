import os

extension Logger {
    private nonisolated static let subsystem = "com.thetpine.workspace.NTUSync"

    nonisolated static let routing = Logger(subsystem: subsystem, category: "routing")
    nonisolated static let liveActivity = Logger(subsystem: subsystem, category: "liveactivity")
    nonisolated static let persistence = Logger(subsystem: subsystem, category: "persistence")
    nonisolated static let location = Logger(subsystem: subsystem, category: "location")
    nonisolated static let motion = Logger(subsystem: subsystem, category: "motion")
}
