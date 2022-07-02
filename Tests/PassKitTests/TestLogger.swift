#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Windows)
import CRT
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Unsupported runtime")
#endif
import Logging
import Foundation

// Prevent name clashes
#if os(macOS) || os(tvOS) || os(iOS) || os(watchOS)
let systemStderr = Darwin.stderr
let systemStdout = Darwin.stdout
#elseif os(Windows)
let systemStderr = CRT.stderr
let systemStdout = CRT.stdout
#elseif canImport(Glibc)
let systemStderr = Glibc.stderr!
let systemStdout = Glibc.stdout!
#elseif canImport(WASILibc)
let systemStderr = WASILibc.stderr!
let systemStdout = WASILibc.stdout!
#else
#error("Unsupported runtime")
#endif

/// A wrapper to facilitate `print`-ing to stderr and stdio that
/// ensures access to the underlying `FILE` is locked to prevent
/// cross-thread interleaving of output.
internal struct StdioOutputStream: TextOutputStream {
    #if canImport(WASILibc)
    internal let file: OpaquePointer
    #else
    internal let file: UnsafeMutablePointer<FILE>
    #endif
    internal let flushMode: FlushMode

    internal func write(_ string: String) {
        string.withCString { ptr in
            #if os(Windows)
            _lock_file(self.file)
            #elseif canImport(WASILibc)
            // no file locking on WASI
            #else
            flockfile(self.file)
            #endif
            defer {
                #if os(Windows)
                _unlock_file(self.file)
                #elseif canImport(WASILibc)
                // no file locking on WASI
                #else
                funlockfile(self.file)
                #endif
            }
            _ = fputs(ptr, self.file)
            if case .always = self.flushMode {
                self.flush()
            }
        }
    }

    /// Flush the underlying stream.
    /// This has no effect when using the `.always` flush mode, which is the default
    internal func flush() {
        _ = fflush(self.file)
    }

    internal static let stderr = StdioOutputStream(file: systemStderr, flushMode: .always)
    internal static let stdout = StdioOutputStream(file: systemStdout, flushMode: .always)

    /// Defines the flushing strategy for the underlying stream.
    internal enum FlushMode {
        case undefined
        case always
    }
}

/// `StreamLogHandler` is a simple implementation of `LogHandler` for directing
/// `Logger` output to either `stderr` or `stdout` via the factory methods.
public struct TestsLogHandler: LogHandler {
    /// Factory that makes a `StreamLogHandler` to directs its output to `stdout`
    public static func standardOutput(label: String) -> TestsLogHandler {
        TestsLogHandler(label: label, stream: StdioOutputStream.stdout)
    }

//    /// Factory that makes a `StreamLogHandler` to directs its output to `stderr`
//    public static func standardError(label: String) -> StreamLogHandler {
//        return StreamLogHandler(label: label, stream: StdioOutputStream.stderr)
//    }

    private let stream: TextOutputStream
    private let label: String

    public var logLevel: Logger.Level = .info

    private var prettyMetadata: String?
    public var metadata = Logger.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    // internal for testing only
    internal init(label: String, stream: TextOutputStream) {
        self.label = label
        self.stream = stream
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {
        let prettyMetadata = metadata?.isEmpty ?? true
            ? self.prettyMetadata
            : self.prettify(self.metadata.merging(metadata!, uniquingKeysWith: { _, new in new }))

        var stream = self.stream
        stream.write("\n")
        stream.write(timestamp())
        if !label.isEmpty {
            stream.write(" \(label)")
        }
        if let file = URL(string: file)?.lastPathComponent {
            stream.write(" \(file):\(line) \(function)")
        } else {
            stream.write(" \(line) \(function)")
        }
        stream.write(" \(level) \(icon(for: level))")
        if !message.description.isEmpty {
            stream.write(" \(message)")
        }
        stream.write("\n")
        if let prettyMetadata, !prettyMetadata.isEmpty {
            stream.write("metadata:\n\(prettyMetadata)")
        }
        stream.write("\n")
    }
    
    private func icon(for level: Logger.Level) -> String {
        switch level {
        case .trace:
            return "🕵️‍♂️"
        case .debug:
            return "👷‍♂️"
        case .info:
            return "ℹ️"
        case .notice:
            return "❕"
        case .warning:
            return "⚠️"
        case .error:
            return "❌"
        case .critical:
            return "‼️"
        }
    }

    private func prettify(_ metadata: Logger.Metadata) -> String? {
        !metadata.isEmpty
            ? metadata.lazy.sorted(by: { $0.key < $1.key }).map { "\t\($0)=\($1)" }.joined(separator: "\n")
            : nil
    }

    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        var timestamp = time(nil)
        let localTime = localtime(&timestamp)
        strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!)
            }
        }
    }
}
