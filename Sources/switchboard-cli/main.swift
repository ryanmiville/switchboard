import Foundation
import SwitchboardCLI
import SwitchboardCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// switchboard: inspect and change how links are routed. Reads and writes the same files as the
// app, with no daemon. Every command accepts --json. It never opens links. This is the one place the
// CLI reads its environment and the clock; everything else gets them passed in.

let (home, env) = Env.fromProcess()
guard let home else {
    FileHandle.standardError.write(Data("error: $HOME isn't set.\n".utf8))
    exit(1)
}
let context = Context(
    home: home, env: env, now: Timestamp(Date()), browsers: Browsers(home: home, env: env),
    terminal: isatty(STDOUT_FILENO) == 1)
let outcome = CommandLineTool.run(Array(CommandLine.arguments.dropFirst()), context: context)

// A closed pipe (`| head`) is not an error worth reporting.
signal(SIGPIPE, SIG_IGN)
func emit(_ text: String, to descriptor: Int32) {
    var bytes = Array(text.utf8)[...]
    while !bytes.isEmpty {
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        if written < 0 && errno == EINTR { continue }
        if written <= 0 { return }
        bytes = bytes.dropFirst(written)
    }
}
emit(outcome.stdout, to: STDOUT_FILENO)
emit(outcome.stderr, to: STDERR_FILENO)
exit(outcome.status)
