import AppKit
import Foundation

enum CLIError: LocalizedError {
    case usage(String)
    var errorDescription: String? {
        switch self {
        case .usage(let text): return text
        }
    }
}

enum CLI {
    /// Launchers (Xcode's debugger, `open`, etc.) can prepend their own
    /// flags, so main.swift can't just check "are there any arguments" to
    /// decide CLI vs GUI mode — it must check the first argument against
    /// this known set (verified empirically: Xcode's Run action injects
    /// extra args that tripped a naive `count > 1` check).
    static let subcommands: Set<String> = ["set", "reset", "restore"]

    nonisolated static func run(_ args: [String]) async -> Int32 {
        guard let command = args.first else {
            printUsage()
            return 64
        }
        do {
            switch command {
            case "set":
                try runSet(Array(args.dropFirst()))
            case "reset":
                try runReset(Array(args.dropFirst()))
            case "restore":
                try await Restorer.restoreAll()
                print("OK: restored icons from cache")
            default:
                printUsage()
                return 64
            }
            return 0
        } catch {
            FileHandle.standardError.write("iconswap: \(error.localizedDescription)\n".data(using: .utf8)!)
            return 1
        }
    }

    private static func runSet(_ args: [String]) throws {
        guard args.count == 2 else {
            throw CLIError.usage("Usage: iconswap set <path.app> <image>")
        }
        let appPath = (args[0] as NSString).standardizingPath
        let imagePath = (args[1] as NSString).standardizingPath
        guard let bundle = Bundle(path: appPath), let bundleID = bundle.bundleIdentifier else {
            throw IconSwapError.appNotFound(path: appPath)
        }
        try IconApplier.apply(imageURL: URL(fileURLWithPath: imagePath), toAppAt: appPath, bundleID: bundleID)
        print("OK: applied icon to \(appPath)")
    }

    private static func runReset(_ args: [String]) throws {
        guard args.count == 1 else {
            throw CLIError.usage("Usage: iconswap reset <path.app>")
        }
        let appPath = (args[0] as NSString).standardizingPath
        try IconApplier.reset(appAt: appPath)
        print("OK: reset icon for \(appPath)")
    }

    private static func printUsage() {
        print("""
        Usage:
          iconswap set <path.app> <image>
          iconswap reset <path.app>
          iconswap restore
        """)
    }
}
