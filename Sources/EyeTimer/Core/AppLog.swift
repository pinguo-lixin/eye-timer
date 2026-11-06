import Foundation

/// 轻量文件日志。
///
/// 用途：诊断「事件到底走了哪条路径」这类问题。
/// `NSLog` 在通过 `open` 启动（无终端）时输出不便收集，
/// 写文件最直接 —— 路径固定为 `~/Library/Logs/EyeTimer/debug.log`。
///
/// 每次启动会清空旧文件，避免无限增长。
enum AppLog {

    /// 日志文件路径
    static let fileURL: URL = {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/EyeTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("debug.log")
        // 启动时清空，避免文件无限增长
        try? Data().write(to: url, options: .atomic)
        return url
    }()

    private static let queue = DispatchQueue(label: "com.eyetimer.log")

    /// 写一行日志
    static func write(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: Self.fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: Self.fileURL, options: .atomic)
                }
            }
        }
        NSLog("[EyeTimer] %@", message)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
