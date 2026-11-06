import Foundation
import ScreenCaptureKit
let sem = DispatchSemaphore(value: 0)
Task {
    let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    for w in content.windows {
        let bid = w.owningApplication?.bundleIdentifier ?? ""
        let nm = w.owningApplication?.applicationName ?? ""
        if bid.contains("eyetimer") {
            print("frame=\(w.frame) level=\(w.windowLayer) name=\(w.title ?? "-")")
        }
    }
    sem.signal()
}
sem.wait()
