import Darwin
import Foundation

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool = false
    var timeoutSeconds: TimeInterval?

    var succeeded: Bool { status == 0 && !timedOut }
}

enum ProcessRunner {
    static func run(
        _ executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        timeoutSeconds: TimeInterval? = nil,
        outputHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = currentDirectory
            }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let outputState = ProcessOutputState(outputHandler: outputHandler)
            stdout.fileHandleForReading.readabilityHandler = { handle in
                outputState.appendStdout(handle.availableData)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                outputState.appendStderr(handle.availableData)
            }

            let timeoutState = ProcessTimeoutState(process: process)
            do {
                try process.run()
                var timeoutTimer: DispatchSourceTimer?
                if let timeoutSeconds, timeoutSeconds > 0 {
                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                    timer.schedule(deadline: .now() + timeoutSeconds)
                    timer.setEventHandler {
                        timeoutState.stopProcessAfterTimeout(timeoutSeconds)
                    }
                    timeoutTimer = timer
                }
                timeoutTimer?.resume()
                process.waitUntilExit()
                timeoutTimer?.cancel()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                throw error
            }

            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            outputState.appendStdout(stdout.fileHandleForReading.readDataToEndOfFile())
            outputState.appendStderr(stderr.fileHandleForReading.readDataToEndOfFile())

            let didTimeOut = timeoutState.timedOut
            var stderrText = outputState.stderrText
            if didTimeOut {
                let message = "The helper timed out after \(Int(timeoutState.timeoutSeconds ?? timeoutSeconds ?? 0)) seconds."
                stderrText = stderrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? message : "\(stderrText)\n\(message)"
            }
            return ProcessResult(
                status: didTimeOut ? -9 : process.terminationStatus,
                stdout: outputState.stdoutText,
                stderr: stderrText,
                timedOut: didTimeOut,
                timeoutSeconds: timeoutState.timeoutSeconds ?? timeoutSeconds
            )
        }.value
    }
}

private final class ProcessOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private let outputHandler: (@Sendable (String) -> Void)?

    init(outputHandler: (@Sendable (String) -> Void)?) {
        self.outputHandler = outputHandler
    }

    var stdoutText: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }

    var stderrText: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stderrData, encoding: .utf8) ?? ""
    }

    func appendStdout(_ data: Data) {
        append(data, toStdout: true)
    }

    func appendStderr(_ data: Data) {
        append(data, toStdout: false)
    }

    private func append(_ data: Data, toStdout: Bool) {
        guard !data.isEmpty else { return }
        lock.lock()
        if toStdout {
            stdoutData.append(data)
        } else {
            stderrData.append(data)
        }
        lock.unlock()

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            outputHandler?(text)
        }
    }
}

private final class ProcessTimeoutState: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var didTimeOut = false
    private var recordedTimeoutSeconds: TimeInterval?

    init(process: Process) {
        self.process = process
    }

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeOut
    }

    var timeoutSeconds: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return recordedTimeoutSeconds
    }

    func stopProcessAfterTimeout(_ seconds: TimeInterval) {
        lock.lock()
        guard process.isRunning else {
            lock.unlock()
            return
        }
        didTimeOut = true
        recordedTimeoutSeconds = seconds
        let pid = process.processIdentifier
        lock.unlock()

        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.killIfStillRunning(pid: pid)
        }
    }

    private func killIfStillRunning(pid: Int32) {
        lock.lock()
        let shouldKill = didTimeOut && process.isRunning
        lock.unlock()
        if shouldKill {
            kill(pid, SIGKILL)
        }
    }
}

struct ToolLookup {
    static func find(_ name: String) -> URL? {
        let candidates = [
            AppConfiguration.projectRoot.appendingPathComponent("Tools/bin/\(name)").path,
            AppConfiguration.projectRoot.appendingPathComponent(".tools/bin/\(name)").path,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        return candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
