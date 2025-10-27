//
//  Log.swift
//  Calc26
//
//  Created by sumpo/azukid on 2025/07/07.
//

import Foundation


enum LogLevel: Int, Comparable {
    case info = 0
    case debug = 1
    case warning = 2
    case error = 3
    case fatal = 4
    
    var prefix: String {
        switch self {
            case .info:    return "(i)"
            case .debug:   return "(d)"
            case .warning: return "(W)"
            case .error:   return "[ERROR]"
            case .fatal:   return "[FATAL]"
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

#if DEBUG
let currentLogLevel: LogLevel = .info
#else
let currentLogLevel: LogLevel = .error
#endif

func log(_ level: LogLevel,
         _ message: String,
         file: String = #file,
         line: Int = #line,
         function: String = #function)
{
    guard currentLogLevel <= level else { return }
    
    let fileName = (file as NSString).lastPathComponent
    print("\(fileName)(\(line)) \(function) \(level.prefix) \(message)")
}

