import Cocoa
import FlutterMacOS
import Foundation

private func silenceInputMethodLogs() {
    let pipe = Pipe()
    let writeHandle = pipe.fileHandleForWriting
    let readHandle = pipe.fileHandleForReading
    
    // Duplicate standard error descriptor
    let originalStderr = dup(STDERR_FILENO)
    
    // Redirect stderr to our pipe
    dup2(writeHandle.fileDescriptor, STDERR_FILENO)
    
    // Read and filter in background thread
    Thread.detachNewThread {
        let originalStderrHandle = FileHandle(fileDescriptor: originalStderr, closeOnDealloc: true)
        
        while true {
            let data = readHandle.availableData
            if data.isEmpty { break }
            
            if let string = String(data: data, encoding: .utf8) {
                let lines = string.components(separatedBy: "\n")
                var filteredLines = [String]()
                for line in lines {
                    if !line.contains("_TIPropertyValueIsValid") &&
                       !line.contains("imkxpc_setApplicationProperty") &&
                       !line.contains("imkxpc_") {
                        filteredLines.append(line)
                    }
                }
                
                if !filteredLines.isEmpty {
                    let filteredString = filteredLines.joined(separator: "\n")
                    if let filteredData = filteredString.data(using: .utf8) {
                        originalStderrHandle.write(filteredData)
                    }
                }
            } else {
                originalStderrHandle.write(data)
            }
        }
    }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    silenceInputMethodLogs()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
