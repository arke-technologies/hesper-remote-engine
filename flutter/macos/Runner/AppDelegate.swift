import Cocoa
import FlutterMacOS

/// Launches that never show a UI: the Hesper agent's headless engine (`--mode …`)
/// and the CLI verbs it (or an operator) runs against the installed engine. Every
/// one of these is handled by the Rust core, which either exits the process or
/// blocks serving; none hands a UI back.
private let hesperNoUIVerbs: Set<String> = [
    "--get-id", "--option", "--password", "--set-session-otp",
    "--set-managed-password", "--version",
]

private func hesperRunsWithoutUI(_ args: [String]) -> Bool {
    let rest = args.dropFirst()
    if rest.contains("--mode") { return true } // Hesper headless sentinel (core_main.rs)
    if let first = rest.first { return hesperNoUIVerbs.contains(first) }
    return false
}

@main
class AppDelegate: FlutterAppDelegate {
    var launched = false;

    /// Hesper: route UI-less launches to the Rust core BEFORE AppKit starts.
    ///
    /// NSApplicationMain checks the process in with LaunchServices as "Hesper Remote".
    /// The agent's managed standby runs this executable as root (`--mode
    /// input_control`). Once that root instance had checked in, a Dock, Finder or
    /// `open -a` launch of the app was routed to it as a reopen. Another user's
    /// process cannot receive that, so the launch failed with -600 and the user
    /// could not open Hesper Remote at all. (Stock RustDesk avoids this only because
    /// its root daemon is the separate `service` executable.)
    ///
    /// For these launches `rustdesk_core_main()` exits the process when the verb is
    /// done, or blocks serving in headless mode. Nothing is checked in, and the
    /// executable, and with it the Screen Recording and Accessibility grants, is
    /// unchanged. Every other launch takes the stock path: NSApplicationMain, then
    /// MainFlutterWindow.awakeFromNib calls rustdesk_core_main() exactly once.
    static func main() {
        if hesperRunsWithoutUI(CommandLine.arguments) {
            _ = rustdesk_core_main()
            exit(0) // the core asked for a UI it was never meant to show here
        }
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
      dummy_method_to_enforce_bundling()
    // https://github.com/leanflutter/window_manager/issues/214
    return false
  }

    override func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if (launched) {
            handle_applicationShouldOpenUntitledFile();
        }
        return true
    }

    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        launched = true;
        NSApplication.shared.activate(ignoringOtherApps: true);
    }
}
