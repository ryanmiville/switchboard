import ArgumentParser
import Foundation
import SwitchboardCore

// Running a command line: parse, dispatch, and render the result as text or one JSON object.
// Reads nothing from the process: the binary passes its home, environment, clock and whether
// stdout is a terminal in a Context, so tests run the real binary against a temporary home.

/// Everything a command reads from outside.
public struct Context: Sendable {
    public var home: Home
    public var env: Env
    public var now: Timestamp
    public var browsers: Browsers
    /// Whether stdout is a terminal: JSON is indented for people, one line for programs.
    public var terminal: Bool

    public init(home: Home, env: Env, now: Timestamp, browsers: Browsers, terminal: Bool) {
        self.home = home
        self.env = env
        self.now = now
        self.browsers = browsers
        self.terminal = terminal
    }
}

/// What a run prints and returns.
public struct Outcome: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
}

/// What a command prints: a JSON report for `--json`, text otherwise.
struct Output {
    var json: any Encodable
    var text: String
}

/// A parsed command that can run.
protocol Runnable {
    var global: GlobalOptions { get }
    func execute(_ session: Session) throws(OperationError) -> Output
}

public enum CommandLineTool {
    /// Runs `arguments` (without the program name).
    public static func run(_ arguments: [String], context: Context) -> Outcome {
        let json = arguments.contains("--json")
        let command: ParsableCommand
        do {
            command = try Root.parseAsRoot(hoistingGlobalOptions(arguments))
        } catch {
            let status = Root.exitCode(for: error).rawValue
            if status == 0 {
                return Outcome(status: 0, stdout: Root.fullMessage(for: error) + "\n", stderr: "")
            }
            if json {
                var message = Root.message(for: error).trimmingCharacters(in: .whitespacesAndNewlines)
                if message.hasPrefix("Error: ") { message.removeFirst("Error: ".count) }
                let oneLine = message.split(whereSeparator: \.isNewline).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                .filter { !$0.isEmpty }.joined(separator: " ")
                return failure(.invalid(oneLine), json: true, terminal: context.terminal)
            }
            return Outcome(status: 2, stdout: "", stderr: Root.fullMessage(for: error) + "\n")
        }
        guard let runnable = command as? Runnable else {
            // A command group named without a subcommand: show its help, as a usage error.
            let help = Root.helpMessage(for: type(of: command))
            if json {
                return failure(
                    .invalid("Name a subcommand. Run with --help to list them."), json: true,
                    terminal: context.terminal)
            }
            return Outcome(status: 2, stdout: "", stderr: help + "\n")
        }
        let session = Session(context: context, global: runnable.global)
        do {
            let output = try runnable.execute(session)
            let stdout =
                runnable.global.json ? JSONText.encode(output.json, terminal: context.terminal) : output.text
            return Outcome(status: 0, stdout: stdout, stderr: "")
        } catch {
            return failure(error, json: runnable.global.json, terminal: context.terminal)
        }
    }

    static func failure(_ error: OperationError, json: Bool, terminal: Bool) -> Outcome {
        if json {
            var body = JSONObject()
            body.set("error", error)
            return Outcome(
                status: error.code.exitCode, stdout: JSONText.encode(body, terminal: terminal), stderr: "")
        }
        var text = "error: \(error.message)\n"
        for candidate in error.candidates { text += Format.candidate(candidate) }
        return Outcome(status: error.code.exitCode, stdout: "", stderr: text)
    }

    /// Moves the global options to the end, so they work before the subcommand too
    /// (`switchboard --json rules list`): ArgumentParser reads them on the leaf command.
    static func hoistingGlobalOptions(_ arguments: [String]) -> [String] {
        var rest: [String] = []
        var global: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                rest += arguments[index...]
                break
            }
            let name = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? argument
            if GlobalOptions.flags.contains(argument) {
                global.append(argument)
            } else if GlobalOptions.options.contains(name) {
                global.append(argument)
                if !argument.contains("="), index + 1 < arguments.count {
                    index += 1
                    global.append(arguments[index])
                }
            } else {
                rest.append(argument)
            }
            index += 1
        }
        return rest + global
    }
}
