import AppKit

// Single-instance enforcement (skip during unit tests).
let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
if !isRunningTests {
    let myBundleID = Bundle.main.bundleIdentifier ?? "com.mikefullerton.Whippet"
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: myBundleID)
    if running.count > 1 {
        for app in running where app != NSRunningApplication.current {
            app.activate()
        }
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
