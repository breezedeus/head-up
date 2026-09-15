import Foundation
import OSLog

/// Compile-time diagnostics switch.
///
/// Preview (debug) builds are produced with:
/// `HEADUP_PREVIEW=1 ./script/build_and_run.sh build`, which passes
/// `-Xswiftc -DHEADUP_DEBUG` to the Swift compiler.
///
/// In preview builds, drift diagnostics are elevated to `.info` (visible in
/// Console.app by default and persisted by the unified logging system) and
/// high-frequency per-sample traces are compiled in. Release builds keep the
/// same events at `.debug` and compile the hot-path traces out entirely.
enum HeadUpTrace {
    /// True only for builds compiled with `-DHEADUP_DEBUG`.
    static let isPreviewBuild: Bool = {
        #if HEADUP_DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Signed, fixed-width angle formatting for compact log lines.
    static func deg(_ value: Double) -> String {
        String(format: "%+.2f°", value)
    }

    /// Evaluation-level drift diagnostics: `.debug` in release, `.info` in preview builds.
    static func drift(_ message: @autoclosure () -> String, logger: Logger = HeadUpLog.privacy) {
        let text = message()
        #if HEADUP_DEBUG
        logger.info("\(text, privacy: .public)")
        #else
        logger.debug("\(text, privacy: .public)")
        #endif
    }

    /// Sample-level drift tracing. Compiled out of release builds to avoid hot-path cost.
    static func driftVerbose(_ message: @autoclosure () -> String, logger: Logger = HeadUpLog.privacy) {
        #if HEADUP_DEBUG
        let text = message()
        logger.info("\(text, privacy: .public)")
        #endif
    }
}
