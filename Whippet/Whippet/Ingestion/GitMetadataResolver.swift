import Foundation

/// Resolves git metadata (branch name, worktree status) for a given directory.
/// Runs git commands with a short timeout to avoid blocking.
final class GitMetadataResolver {

    static let shared = GitMetadataResolver()

    /// Cache to avoid re-running git for the same cwd within a short period.
    private var cache: [String: (branch: String, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 30

    func resolveBranch(cwd: String) -> String {
        // Check cache
        if let cached = cache[cwd], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.branch
        }

        let branch = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd)
        cache[cwd] = (branch: branch, timestamp: Date())
        return branch
    }

    private func runGit(args: [String], cwd: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd] + args
        process.environment = ["GIT_TERMINAL_PROMPT": "0"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // 2-second timeout
            let deadline = DispatchTime.now() + .seconds(2)
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                process.waitUntilExit()
                done.signal()
            }
            if done.wait(timeout: deadline) == .timedOut {
                process.terminate()
                return ""
            }

            guard process.terminationStatus == 0 else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
