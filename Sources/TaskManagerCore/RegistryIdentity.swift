import IOKit

/// Registry entry numbers change at reboot; the IOService topology path is suitable
/// for local visibility preferences for a device in the same hardware location.
enum RegistryIdentity {
    static func path(of entry: io_registry_entry_t) -> String? {
        var path = [CChar](repeating: 0, count: 4096)
        guard IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS else { return nil }
        return String(cString: path)
    }
}
