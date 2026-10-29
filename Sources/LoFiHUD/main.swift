import AppKit

let args = CommandLine.arguments

// `LoFiHUD --uninstall [--delete-music | --keep-music]`
if args.contains("--uninstall") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate()
    var deleteMusic: Bool? = nil
    if args.contains("--delete-music") { deleteMusic = true }
    if args.contains("--keep-music") || args.contains("--preserve-music") { deleteMusic = false }
    Uninstaller.run(deleteMusic: deleteMusic)
    exit(0)
}

let instance = SingleInstance()
guard instance.acquire() else {
    // Already running: surface the existing instance's Settings and exit.
    instance.notifyRunningInstance()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(instance: instance)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
