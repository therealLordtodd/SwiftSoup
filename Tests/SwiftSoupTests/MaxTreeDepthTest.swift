//
//  MaxTreeDepthTest.swift
//  SwiftSoup
//

import XCTest
@testable import SwiftSoup

class MaxTreeDepthTest: XCTestCase {

    private let limit = 512
    private lazy var limited = ParseSettings.htmlDefault.withMaxTreeDepth(limit)

    // MARK: - helpers

    /// Deepest element nesting in the finished document, counting `html`/`body` shells but not the
    /// `Document` itself -- the same convention `TreeBuilder.enforceTreeDepth` bounds.
    private func maxElementDepth(_ doc: Document) -> Int {
        var best = 0
        var level: [Element] = doc.children().array()
        var depth = 0
        while !level.isEmpty {
            depth += 1
            best = depth
            var next: [Element] = []
            for element in level {
                next.append(contentsOf: element.children().array())
            }
            level = next
        }
        return best
    }

    private func assertThrowsDepthExceeded(_ html: String,
                                           _ message: String,
                                           file: StaticString = #filePath,
                                           line: UInt = #line) {
        do {
            _ = try Parser.parseBodyFragment(html, "", settings: limited)
            XCTFail("expected .TreeDepthExceeded for \(message)", file: file, line: line)
        } catch let Exception.Error(type, _) {
            XCTAssertEqual(type, ExceptionType.TreeDepthExceeded, message, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error) for \(message)", file: file, line: line)
        }
    }

    // MARK: - (a) default settings are unchanged

    func testDefaultSettingsParseDeeplyNestedDivs() throws {
        let html = String(repeating: "<div>", count: 1000)
        let doc = try Parser.parseBodyFragment(html, "")
        // html shell + body + 1000 divs
        XCTAssertEqual(maxElementDepth(doc), 1002)
        XCTAssertEqual(ParseSettings.htmlDefault.maximumTreeDepth(), ParseSettings.unlimitedTreeDepth)
    }

    // MARK: - (b) the boundary

    func testNestingBelowLimitParses() throws {
        // Fragment parsing builds doc -> html(shell) -> div*N, so 511 divs reach depth 512.
        let html = String(repeating: "<div>", count: 511)
        let doc = try Parser.parseBodyFragment(html, "", settings: limited)
        XCTAssertNotNil(doc.body())
    }

    func testNestingAboveLimitThrows() {
        assertThrowsDepthExceeded(String(repeating: "<div>", count: 513), "513 nested divs")
    }

    // MARK: - (c) end tag that cannot close through a scope boundary

    func testObjectScopeBoundaryNestingThrows() {
        // </div> cannot close through the <object> scope boundary, so each repetition adds two
        // levels: real depth is ~1200 even though only 600 divs are written.
        let html = String(repeating: "<div><object></div>", count: 600) + "x"
        assertThrowsDepthExceeded(html, "600 x <div><object></div>")
    }

    // MARK: - (c2) form end tag: stack shrinks but the tree does not

    func testFormEndTagNestingThrows() {
        // </form> removes the form from the stack of open elements without popping the still-open
        // <div> inside it. Each repetition therefore adds two DOM ancestors while the stack grows
        // by only one -- a stack-depth check would not catch this.
        let html = String(repeating: "<form><div></form>", count: 300) + "x"
        assertThrowsDepthExceeded(html, "300 x <form><div></form>")
    }

    func testFormEndTagNestingParsesWhenUnlimited() throws {
        let html = String(repeating: "<form><div></form>", count: 300) + "x"
        let doc = try Parser.parseBodyFragment(html, "")
        XCTAssertGreaterThan(maxElementDepth(doc), 512)
    }

    // MARK: - (d) parser-created structure counts

    func testImpliedTableStructureCountsTowardLimit() {
        // Each <table><tr><td> contributes table + implied tbody + tr + td = 4 levels.
        let html = String(repeating: "<table><tr><td>", count: 300)
        assertThrowsDepthExceeded(html, "300 nested table/tr/td")
    }

    // MARK: - (e) breadth is not depth

    func testManySiblingsParseUnderLimit() throws {
        let html = String(repeating: "<p>x</p>", count: 10_000)
        let doc = try Parser.parseBodyFragment(html, "", settings: limited)
        XCTAssertEqual(try doc.select("p").count, 10_000)
    }

    // MARK: - (f) no stale state, and the partial tree is released

    func testParserIsReusableAfterDepthThrowAndPartialTreeIsReleased() throws {
        let parser = Parser.htmlParser()
        parser.settings(limited)

        weak var partial: Document?
        do {
            let builder = parser.getTreeBuilder()
            XCTAssertThrowsError(try parser.parseInput(String(repeating: "<div>", count: 2000), ""))
            partial = builder.doc
        }

        // A fresh parse on the same Parser must work and must drop the abandoned tree.
        let good = try parser.parseInput("<p>hello</p>", "")
        XCTAssertEqual("hello", try good.select("p").text())
        XCTAssertNil(partial, "the partially built document should have been released")

        // And the same Parser still refuses a second over-deep document.
        XCTAssertThrowsError(try parser.parseInput(String(repeating: "<div>", count: 2000), ""))
    }

    // MARK: - XML tree builder honours the same limit

    func testXmlTreeBuilderHonoursLimit() {
        let xml = String(repeating: "<a>", count: 600)
        let builder = XmlTreeBuilder()
        XCTAssertThrowsError(try builder.parse(xml.utf8Array, "".utf8Array,
                                               ParseErrorList.noTracking(),
                                               ParseSettings.preserveCase.withMaxTreeDepth(limit)))
    }

    // MARK: - the sanitizer entry point honours the limit

    func testCleanHonoursLimit() throws {
        let deep = String(repeating: "<form><div></form>", count: 300) + "x"
        // Unlimited (default) still cleans it.
        XCTAssertNotNil(try SwiftSoup.clean(deep, "", Whitelist.relaxed()))
        // With a limit, clean refuses rather than building the tree.
        XCTAssertThrowsError(try SwiftSoup.clean(deep, "", Whitelist.relaxed(), settings: limited)) { error in
            guard case Exception.Error(let type, _) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(type, ExceptionType.TreeDepthExceeded)
        }
    }
}
