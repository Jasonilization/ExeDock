import Foundation
import Darwin

/// One-time launch cleanup for Wine helper processes a previous ExeDock session left behind. Wine
/// keeps a `wineserver` running per prefix as that prefix's coordinator, plus helper daemons
/// (winedevice.exe, services.exe, …) it spawns underneath - by design they persist so the next wine
/// command in that prefix starts fast. If wineserver itself is ever killed abruptly instead of shut
/// down cleanly (Force Quitting ExeDock, killing a hung game from Activity Monitor, a crash), those
/// helper daemons can be left running with no coordinator at all - reparented to launchd (PPID 1),
/// doing nothing useful, just burning CPU/battery forever since nothing will ever tell them to exit.
/// (This is exactly how three `winedevice.exe` processes ended up idling on this machine for hours,
/// together costing several percent of a whole CPU core continuously.)
///
/// This only sweeps when *zero* wineserver processes are running anywhere on the system - if any
/// wineserver is alive (ExeDock's own or a Sikarugir wrapper's), a PPID-1 helper might still
/// legitimately belong to it, so it's left alone rather than risk killing something live.
enum WineProcessReaper {
    private static let orphanableBinaries = ["winedevice.exe", "services.exe", "plugplay.exe", "rpcss.exe"]

    static func sweepOrphans() {
        let psOutput = run("/bin/ps", ["-axo", "pid=,ppid=,comm="])
        guard !psOutput.isEmpty else { return }

        let lines = psOutput.split(separator: "\n").map(String.init)
        let hasLiveWineserver = lines.contains { $0.localizedCaseInsensitiveContains("wineserver") }
        guard !hasLiveWineserver else { return }

        for line in lines {
            let fields = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, fields[1] == "1", let pid = Int32(fields[0]) else { continue }
            let comm = fields[2...].joined(separator: " ")
            guard orphanableBinaries.contains(where: { comm.localizedCaseInsensitiveContains($0) }) else { continue }
            kill(pid, SIGKILL)
        }
    }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
