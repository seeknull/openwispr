import XCTest
@testable import WhispCore

final class TranscriptBufferTests: XCTestCase {
    func testIngestCompletedLine_appendsTrailingSpaceByDefault() {
        var buf = TranscriptBuffer()
        XCTAssertEqual(buf.ingestCompletedLine("hello world"), "hello world ")
        XCTAssertEqual(buf.emittedLineCount, 1)
    }

    func testIngestCompletedLine_trimsWhitespace() {
        var buf = TranscriptBuffer()
        XCTAssertEqual(buf.ingestCompletedLine("  hi  "), "hi ")
    }

    func testIngestCompletedLine_returnsNilForEmpty() {
        var buf = TranscriptBuffer()
        XCTAssertNil(buf.ingestCompletedLine(""))
        XCTAssertNil(buf.ingestCompletedLine("   \n\t  "))
        XCTAssertEqual(buf.emittedLineCount, 0)
    }

    func testWithoutTrailingSpace() {
        var buf = TranscriptBuffer(appendsTrailingSpace: false)
        XCTAssertEqual(buf.ingestCompletedLine("hello"), "hello")
    }

    func testReset_zeroesCount() {
        var buf = TranscriptBuffer()
        _ = buf.ingestCompletedLine("one")
        _ = buf.ingestCompletedLine("two")
        XCTAssertEqual(buf.emittedLineCount, 2)
        buf.reset()
        XCTAssertEqual(buf.emittedLineCount, 0)
    }
}
