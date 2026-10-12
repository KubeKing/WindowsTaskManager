import Foundation
import Darwin

public enum ProcessActionError: LocalizedError {
    case exited, identityChanged, protectedProcess, system(String)
    public var errorDescription: String? {
        switch self {
        case .exited: return "This process has already exited. Refresh the list and select a running process."
        case .identityChanged: return "The selected process has exited and its ID was reused. Select the process again."
        case .protectedProcess: return "This process is protected. Use the application’s own Quit command or macOS system controls."
        case .system(let reason): return reason
        }
    }
}

public enum ProcessActionPolicy {
    public static func validate(requested: ProcessIdentity, current: ProcessIdentity?, selfPID: Int32) throws {
        guard requested.pid > 1, requested.pid != selfPID else { throw ProcessActionError.protectedProcess }
        guard let current else { throw ProcessActionError.exited }
        guard requested == current else { throw ProcessActionError.identityChanged }
    }
}

public enum ProcessActions {
    public static func terminate(_ identity: ProcessIdentity, force: Bool) throws {
        try validate(identity)
        guard Darwin.kill(identity.pid, force ? SIGKILL : SIGTERM) == 0 else { throw ProcessActionError.system(String(cString: strerror(errno))) }
    }
    public static func setPriority(_ identity: ProcessIdentity, nice: Int32) throws {
        try validate(identity)
        guard (-20...20).contains(nice) else { throw ProcessActionError.system("Priority must be between −20 and 20.") }
        guard Darwin.setpriority(PRIO_PROCESS, UInt32(identity.pid), nice) == 0 else { throw ProcessActionError.system(String(cString: strerror(errno))) }
    }
    private static func validate(_ identity: ProcessIdentity) throws {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(identity.pid, &buffer, UInt32(buffer.count)) > 0 {
            let name = URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
            if ["launchd", "kernel_task", "WindowServer", "loginwindow", "watchdogd"].contains(name) { throw ProcessActionError.protectedProcess }
        }
        try ProcessActionPolicy.validate(requested: identity, current: SystemSampler.identity(pid: identity.pid), selfPID: getpid())
    }
}
