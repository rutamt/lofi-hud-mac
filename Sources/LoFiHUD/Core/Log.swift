import os

/// Unified logging. View with: `log stream --predicate 'subsystem == "com.rutamt.lofihud"'`
enum Log {
    static let app = Logger(subsystem: "com.rutamt.lofihud", category: "app")
    static let audio = Logger(subsystem: "com.rutamt.lofihud", category: "audio")
    static let library = Logger(subsystem: "com.rutamt.lofihud", category: "library")
    static let config = Logger(subsystem: "com.rutamt.lofihud", category: "config")
}
