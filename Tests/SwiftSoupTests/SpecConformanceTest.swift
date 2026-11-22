import XCTest
import SwiftSoup
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Four places the HTML tree builder and tokenizer diverged from the HTML
/// parsing spec in ways that put hidden text into a document's text, or made
/// a parse quadratic (found by an independent review of PodcastKit's feed
/// text, 2026-11-21; fixed in Todd's fork as one spec-conformance change).
final class SpecConformanceTest: XCTestCase {

    // MARK: - The self-closing flag is ignored on raw-text and RCDATA elements

    /// The spec ignores the self-closing flag on non-void elements; a
    /// browser keeps `<script/>` open, so what follows up to `</script>` is
    /// script data, not body text.
    func testASelfClosedScriptStaysOpenUntilItsEndTag() throws {
        let doc = try SwiftSoup.parse("<p>A<script type=\"text/plain\"/>HIDDEN</script>B</p>")
        XCTAssertEqual(try doc.body()!.text(), "AB")
        XCTAssertEqual(try doc.select("script").first()!.data(), "HIDDEN")
    }

    func testOtherSelfClosedRawTextElementsStayOpen() throws {
        XCTAssertEqual(try SwiftSoup.parse("<p>A<style/>p{}</style>B</p>").body()!.text(), "AB")
        XCTAssertEqual(try SwiftSoup.parse("<p>A<xmp/>raw</xmp>B</p>").select("xmp").first()!.text(), "raw")
        let textarea = try SwiftSoup.parse("<p>A<textarea/>value</textarea>B</p>").select("textarea").first()!
        XCTAssertEqual(try textarea.text(), "value")
        let title = try SwiftSoup.parse("<title/>Name</title><p>Body</p>")
        XCTAssertEqual(try title.title(), "Name")
        XCTAssertEqual(try title.body()!.text(), "Body")
    }

    /// Unknown and void elements keep the existing self-closing handling.
    func testSelfClosingStillAppliesElsewhere() throws {
        let doc = try SwiftSoup.parse("<p>A<foo/>B<br/>C</p>")
        XCTAssertEqual(try doc.select("foo").first()!.childNodeSize(), 0)
        XCTAssertEqual(try doc.body()!.text(), "ABC")
    }

    // MARK: - template is a scope boundary

    /// `template` bounds the default, button, list-item and table scopes. A
    /// `<div>` inside a template must not close a `<p>` outside it and carry
    /// the template's content out into the body.
    func testATemplateBoundsTheScopeOfAnOuterParagraph() throws {
        let doc = try SwiftSoup.parse("<p>One<template><div>HIDDEN</div></template>Two</p>")
        let template = try doc.select("template").first()!
        XCTAssertEqual(try template.select("div").first()?.text(), "HIDDEN")
        let paragraph = try doc.select("p").first()!
        XCTAssertTrue(paragraph.children().contains(template), "the template was moved out of its paragraph")
        XCTAssertEqual(try doc.select("body > div").size(), 0, "template content leaked into the body")
    }

    func testAnEndTagInsideATemplateDoesNotCloseAnOuterElement() throws {
        let doc = try SwiftSoup.parse("<div id=outer><template></div><span>in</span></template><span id=after>x</span></div>")
        let outer = try doc.getElementById("outer")!
        XCTAssertNotNil(try outer.getElementById("after"), "</div> inside the template closed the outer div")
    }

    // MARK: - CDATA is a bogus comment in HTML content

    /// `<![CDATA[` is only CDATA in foreign content (SVG, MathML); in HTML
    /// content it is a bogus comment, as the tokenizer's own todo said.
    func testCDATAInHTMLContentIsAComment() throws {
        let doc = try SwiftSoup.parse("<div id=1>A <![CDATA[hidden words]]> B</div>")
        let div = try doc.getElementById("1")!
        XCTAssertEqual(try div.text(), "A B")
        XCTAssertTrue(div.getChildNodes().contains { $0 is Comment })
    }

    func testCDATAInSVGIsText() throws {
        let doc = try SwiftSoup.parse("<svg><text><![CDATA[a < b]]></text></svg>")
        XCTAssertEqual(try doc.select("text").first()!.text(), "a < b")
    }

    func testCDATAAfterLeavingSVGIsACommentAgain() throws {
        let doc = try SwiftSoup.parse("<svg><text>s</text></svg><p>A<![CDATA[hidden]]>B</p>")
        XCTAssertEqual(try doc.select("p").first()!.text(), "AB")
    }

    // MARK: - RCDATA's end-tag lookup is not repeated

    /// Each `<letter` inside a title or textarea asked whether `</title>`
    /// appears later, scanning ahead every time: a title full of tags was
    /// quadratic. Once found, it is remembered for the rest of the element.
    func testATitleFullOfTagsParsesInLinearTime() throws {
        func make(_ n: Int) -> String {
            "<title>" + String(repeating: "<b>x", count: n) + "</title><p>Body</p>"
        }
        let small = make(5_000)
        let large = make(20_000)
        _ = try SwiftSoup.parse(small)
        let smallSeconds = try threadCPUSeconds { _ = try SwiftSoup.parse(small) }
        let largeSeconds = try threadCPUSeconds { _ = try SwiftSoup.parse(large) }
        XCTAssertLessThan(
            largeSeconds, max(smallSeconds, 0.001) * 9,
            "4x the title took \(largeSeconds / max(smallSeconds, 0.001))x the CPU (\(smallSeconds) s -> \(largeSeconds) s)"
        )
        // And the parse is still right: the tags are title text.
        let doc = try SwiftSoup.parse(make(3))
        XCTAssertEqual(try doc.title(), "<b>x<b>x<b>x")
        XCTAssertEqual(try doc.body()!.text(), "Body")
    }

    /// The remembered answer does not outlive its element: a later title
    /// with no end tag still breaks out at its first tag, as before.
    func testTheLookupIsNotCarriedIntoTheNextTitle() throws {
        let doc = try SwiftSoup.parse("<title>one</title><title>two<b>bold")
        XCTAssertEqual(try doc.select("title").last()!.text(), "two")
    }

    // MARK: - Helpers

    private func threadCPUSeconds(_ body: () throws -> Void) throws -> Double {
        var start = timespec()
        var end = timespec()
        try XCTSkipUnless(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &start) == 0, "no thread CPU clock")
        try body()
        XCTAssertEqual(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &end), 0, "the thread CPU clock failed")
        return Double(end.tv_sec - start.tv_sec) + Double(end.tv_nsec - start.tv_nsec) / 1e9
    }
}
