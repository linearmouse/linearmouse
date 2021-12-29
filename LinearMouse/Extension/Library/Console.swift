//
//  Console.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/1/6.
//

import Foundation
import os.log

@objc protocol ConsoleExport: JSExport {
    func log()
    func info()
    func warn()
    func error()
}

enum LogLevel {
    case log, info, warn, error
}

protocol Logger {
    func logger(logLevel: LogLevel, message: String)
}

fileprivate class DefaultLogger: Logger {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Extension")

    let extensionName: String

    init(extensionName: String) {
        self.extensionName = extensionName
    }

    func logger(logLevel: LogLevel, message: String) {
        let type: OSLogType = {
            switch logLevel {
            case .log: return .`default`
            case .info: return .info
            case .warn: return .error
            case .error: return .error
            }
        }()
        os_log("[%{public}@] %{public}@", log: Self.log, type: type, extensionName, message)
    }
}

@objc class Console: NSObject, Library, ConsoleExport {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
        super.init()
    }

    convenience init(extensionName: String) {
        self.init(logger: DefaultLogger(extensionName: extensionName))
    }

    func registerInContext(_ context: JSContext) {
        context.setObject(self, forKeyedSubscript: "console" as NSString)
    }

    private func callLogger(logLevel: LogLevel, args: [Any]) {
        let message = args.map { String(describing: $0) }.joined(separator: " ")
        logger.logger(logLevel: logLevel, message: message)
    }

    func log() {
        let args = JSContext.currentArguments() ?? []
        callLogger(logLevel: .log, args: args)
    }

    func info() {
        let args = JSContext.currentArguments() ?? []
        callLogger(logLevel: .info, args: args)
    }

    func warn() {
        let args = JSContext.currentArguments() ?? []
        callLogger(logLevel: .warn, args: args)
    }

    func error() {
        let args = JSContext.currentArguments() ?? []
        callLogger(logLevel: .error, args: args)
    }
}
