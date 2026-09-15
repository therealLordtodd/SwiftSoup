//
//  MaxParseWorkTest.swift
//  SwiftSoup
//

import XCTest
@testable import SwiftSoup

class MaxParseWorkTest: XCTestCase {

    /// Paragraphs wrapped in `depth` divs: the same content costs more to parse the deeper it is
    /// nested, which is what a depth limit alone does not capture.
    private func nested(depth: Int, paragraphs: Int) -> String {
        return String(repeating: "<div>", count: depth)
             + String(repeating: "<p>x</p>", count: paragraphs)
             + String(repeating: "</div>", count: depth)
    }

    private func ordinaryDocument(repeating: Int) -> String {
        return String(repeating: "<div class=\"row\"><p>hello <b>world</b></p><ul><li>a</li><li>b</li></ul></div>",
                      count: repeating)
    }

    /// Parse through the public `Parser` API and report the work it charged. Everything in this
    /// file measures and asserts on the same entry point, since the work a document costs depends
    /// on how it is parsed (a body fragment does less than a whole document).
    @discardableResult
    private func parse(_ html: String, _ settings: ParseSettings, work: UnsafeMutablePointer<Int>? = nil) throws -> Document {
        let parser = Parser.htmlParser()
        parser.settings(settings)
        let doc = try parser.parseInput(html, "")
        work?.pointee = parser.getTreeBuilder().parseWork
        return doc
    }

    private func work(parsing html: String) throws -> Int {
        var used = 0
        _ = try parse(html, ParseSettings.htmlDefault.withMaxParseWork(Int.max - 1), work: &used)
        return used
    }

    // MARK: - default is unchanged

    func testDefaultSettingsHaveNoBudget() throws {
        XCTAssertEqual(ParseSettings.htmlDefault.maximumParseWork(), ParseSettings.unlimitedParseWork)
        let doc = try SwiftSoup.parse(nested(depth: 200, paragraphs: 200))
        XCTAssertEqual(200, try doc.select("p").size())
    }

    // MARK: - an ordinary document sits far under a workable budget

    func testOrdinaryDocumentStaysFarUnderBudget() throws {
        let html = ordinaryDocument(repeating: 1_200)
        XCTAssertGreaterThan(html.utf8.count, 80 * 1024)

        let used = try work(parsing: html)
        // Size a budget the way a caller would: measure a representative document, leave headroom.
        let budget = used * 4
        let doc = try parse(html, ParseSettings.htmlDefault.withMaxParseWork(budget))
        XCTAssertEqual(1_200, try doc.select("div.row").size())
    }

    // MARK: - nesting is what the budget catches

    func testDeeplyNestedDocumentExceedsABudgetThatFlatContentDoesNot() throws {
        let flat = nested(depth: 4, paragraphs: 4_000)
        let deep = nested(depth: 400, paragraphs: 4_000)

        let flatWork = try work(parsing: flat)
        let deepWork = try work(parsing: deep)
        // Same number of paragraphs; the nested one costs far more.
        XCTAssertGreaterThan(deepWork, flatWork * 10)

        let budget = flatWork * 2
        let settings = ParseSettings.htmlDefault.withMaxParseWork(budget)

        // The flat document still parses under that budget.
        XCTAssertNoThrow(try parse(flat, settings))

        // The nested one is refused.
        do {
            _ = try parse(deep, settings)
            XCTFail("expected the nested document to exceed the budget")
        } catch let Exception.Error(type, _) {
            XCTAssertEqual(ExceptionType.ParseBudgetExceeded, type)
        }
    }

    func testBudgetOfZeroRefusesImmediately() {
        let settings = ParseSettings.htmlDefault.withMaxParseWork(0)
        XCTAssertThrowsError(try parse("<p>x</p>", settings)) { error in
            guard case Exception.Error(let type, _) = error else { return XCTFail("unexpected \(error)") }
            XCTAssertEqual(ExceptionType.ParseBudgetExceeded, type)
        }
    }

    // MARK: - the work count is a function of the input, not the machine

    func testWorkCountIsDeterministic() throws {
        let html = nested(depth: 30, paragraphs: 300)
        let first = try work(parsing: html)
        let second = try work(parsing: html)
        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first, 0)
    }

    // MARK: - the builder is reusable after a refusal

    func testParserIsReusableAfterBudgetRefusal() throws {
        let parser = Parser.htmlParser()
        parser.settings(ParseSettings.htmlDefault.withMaxParseWork(500))

        XCTAssertThrowsError(try parser.parseInput(nested(depth: 100, paragraphs: 500), ""))

        // A fresh parse on the same Parser starts from a clean budget.
        parser.settings(ParseSettings.htmlDefault)
        let recovered = try parser.parseInput("<p>plain</p>", "")
        XCTAssertEqual("<p>plain</p>", try recovered.body()?.html())

        // And the same Parser still refuses when the budget is put back.
        parser.settings(ParseSettings.htmlDefault.withMaxParseWork(500))
        XCTAssertThrowsError(try parser.parseInput(nested(depth: 100, paragraphs: 500), ""))
    }

    // MARK: - depth limit and work budget are independent

    func testWorkBudgetCatchesWhatADepthLimitDoesNot() throws {
        // Depth 400 is under a 512 depth limit, but the work is not.
        let deep = nested(depth: 400, paragraphs: 4_000)
        let settings = ParseSettings.htmlDefault
            .withMaxTreeDepth(512)
            .withMaxParseWork(try work(parsing: nested(depth: 4, paragraphs: 4_000)) * 2)
        XCTAssertThrowsError(try parse(deep, settings)) { error in
            guard case Exception.Error(let type, _) = error else { return XCTFail("unexpected \(error)") }
            XCTAssertEqual(ExceptionType.ParseBudgetExceeded, type)
        }
    }

    // MARK: - every entry point is bounded, not just the document one

    /// The budget belongs to the parse, so every route into the tree builder has to honour it.
    /// The fragment routes set up their parse differently from the document route, and an earlier
    /// version of this feature charged work through a per-node back-reference that the fragment
    /// setup left unset -- so these ran unbounded while the document route refused.
    func testFragmentRoutesHonourTheBudget() throws {
        let deep = nested(depth: 200, paragraphs: 2_000)
        let budget = ParseSettings.htmlDefault.withMaxParseWork(50_000)

        func expectRefusal(_ label: String, _ body: () throws -> Void) {
            do {
                try body()
                XCTFail("\(label) ignored the parse work budget")
            } catch let Exception.Error(type, _) {
                XCTAssertEqual(ExceptionType.ParseBudgetExceeded, type, label)
            } catch {
                XCTFail("\(label): unexpected error \(error)")
            }
        }

        expectRefusal("Parser.parseFragment") {
            let shell = Document.createShell("".utf8Array)
            _ = try Parser.parseFragment(deep, shell.body(), "".utf8Array, settings: budget)
        }
        expectRefusal("Parser.parseBodyFragment") {
            _ = try Parser.parseBodyFragment(deep, "", settings: budget)
        }
        expectRefusal("SwiftSoup.parseBodyFragment") {
            _ = try SwiftSoup.parseBodyFragment(deep, "", settings: budget)
        }
        expectRefusal("SwiftSoup.clean") {
            _ = try SwiftSoup.clean(deep, "", Whitelist.relaxed(), settings: budget)
        }
        expectRefusal("SwiftSoup.isValid") {
            _ = try SwiftSoup.isValid(deep, Whitelist.relaxed(), settings: budget)
        }
    }

    func testXmlTreeBuilderHonoursTheBudget() {
        let xml = String(repeating: "<a>", count: 400) + String(repeating: "</a>", count: 400)
        let builder = XmlTreeBuilder()
        // 400 elements, so a budget of 100 must stop it part way.
        let budget = ParseSettings.preserveCase.withMaxParseWork(100)
        XCTAssertThrowsError(try builder.parse(xml.utf8Array, "".utf8Array,
                                               ParseErrorList.noTracking(), budget)) { error in
            guard case Exception.Error(let type, _) = error else { return XCTFail("unexpected \(error)") }
            XCTAssertEqual(ExceptionType.ParseBudgetExceeded, type)
        }
    }
}
