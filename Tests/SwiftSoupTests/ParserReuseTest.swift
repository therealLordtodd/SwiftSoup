//
//  ParserReuseTest.swift
//  SwiftSoup
//

import XCTest
@testable import SwiftSoup

class ParserReuseTest: XCTestCase {

    func testReusedParserDoesNotLeakFormattingElements() throws {
        let parser = Parser.htmlParser()

        // The <b> is never closed, so it is still an active formatting element at the end.
        let first = try parser.parseInput("<p><b>bold", "")
        XCTAssertEqual("<p><b>bold</b></p>", try first.body()?.html())

        // The next parse must not inherit it.
        let second = try parser.parseInput("<p>plain</p>", "")
        XCTAssertEqual("<p>plain</p>", try second.body()?.html())
        XCTAssertEqual(0, try second.select("b").count)

        // Leaked state also used to swallow content outright, not just add to it.
        let third = try parser.parseInput("<div>x</div>", "")
        XCTAssertEqual("x", try third.select("div").text())
    }

    func testReusedParserDoesNotLeakFormElement() throws {
        let parser = Parser.htmlParser()

        let first = try parser.parseInput("<form><input name=\"a\">", "")
        XCTAssertEqual(1, try first.select("form input").count)

        // The second document has no form, so its input must not be associated with the first one.
        let second = try parser.parseInput("<input name=\"b\">", "")
        XCTAssertEqual(0, try second.select("form").count)
        XCTAssertEqual(1, try second.select("input").count)
    }

    func testReusedParserRecoversFromAThrownParse() throws {
        let builder = AbortingHtmlTreeBuilder()
        let parser = Parser.htmlParser()
        parser.setTreeBuilder(builder)

        // Aborts with the document fully built and <b> still open, so every scrap of per-parse
        // state is populated when the error propagates out.
        XCTAssertThrowsError(try parser.parseInput("<p><b>bold", ""))

        builder.aborts = false
        let recovered = try parser.parseInput("<p>plain</p>", "")
        XCTAssertEqual("<p>plain</p>", try recovered.body()?.html())
        XCTAssertEqual(0, try recovered.select("b").count)
    }
}

/// Throws at end of input, to model a parse that aborts after building part of the tree.
private final class AbortingHtmlTreeBuilder: HtmlTreeBuilder {
    var aborts = true

    override func process(_ token: Token) throws -> Bool {
        if aborts, token.type == Token.TokenType.EOF {
            throw Exception.Error(type: .IllegalArgumentException, Message: "aborted")
        }
        return try super.process(token)
    }
}
