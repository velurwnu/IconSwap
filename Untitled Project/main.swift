import AppKit
import SwiftUI

// No @main here: this file is the entry point instead. When invoked with
// arguments, it runs as the "iconswap" CLI (set/reset/restore); with no
// arguments, it launches the SwiftUI app. This keeps GUI and CLI as a single
// signed binary, so only one code identity ever needs the App Management
// TCC grant.
if let first = CommandLine.arguments.dropFirst().first, CLI.subcommands.contains(first) {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let code = await Task.detached { await CLI.run(arguments) }.value
    exit(code)
} else {
    IconSwapApp.main()
}
