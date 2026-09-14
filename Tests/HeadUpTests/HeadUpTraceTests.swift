import Foundation
import Testing
@testable import HeadUp

struct HeadUpTraceTests {
    @Test func traceCallsAreSafeAndPreviewFlagOffForNormalBuilds() {
        // The test target is compiled without -DHEADUP_DEBUG.
        #expect(!HeadUpTrace.isPreviewBuild)
        HeadUpTrace.drift("probe evaluation line")
        HeadUpTrace.driftVerbose("probe sample line")
        #expect(HeadUpTrace.deg(-1.25).hasPrefix("-"))
        #expect(HeadUpTrace.deg(2).hasSuffix("°"))
    }
}
