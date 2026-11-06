import Foundation
import ScreenCaptureKit
let sem = DispatchSemaphore(value: 0)
Task {
    let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    for w in content.windows {
        let nm = w.owningApplication?.applicationName ?? "?"
        let bid = w.owningApplication?.bundleIdentifier ?? "?"
        if bid.contains("eyetimer") || nm.lowercased().contains("finder") {
            print("\(nm) [\(bid)] level=\(w.windowLayer) frame=\(w.frame) onScreen=\(w.isOnScreen)")
        }
    }
    sem.signal()
}
sem.wait()
