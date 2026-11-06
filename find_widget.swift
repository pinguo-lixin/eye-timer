import Foundation
import ScreenCaptureKit
import AppKit

let sem = DispatchSemaphore(value: 0)
Task {
    let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    for w in content.windows {
        let bid = w.owningApplication?.bundleIdentifier ?? ""
        if bid.contains("eyetimer") {
            print("frame=\(w.frame) level=\(w.windowLayer) onScreen=\(w.isOnScreen)")
        }
    }
    sem.signal()
}
sem.wait()
