import AppKit

if let hookExitCode = AgentHookCommand.runIfRequested() {
  exit(hookExitCode)
}

if let hookStatusExitCode = HookStatusCommand.runIfRequested() {
  exit(hookStatusExitCode)
}

do {
  try AgentIPC.publishCurrentExecutable()
} catch {
  fputs("[TmuxVTab] Failed to publish hook client: \(error)\n", stderr)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
