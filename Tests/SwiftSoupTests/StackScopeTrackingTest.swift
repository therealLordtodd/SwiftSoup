//
//  StackScopeTrackingTest.swift
//  SwiftSoup
//

import XCTest
import SwiftSoup

/// The tree builder keeps a side index of where `p` and `button` sit on the stack of open elements
/// so it can answer "is there a p in button scope?" without walking the stack. These exercise the
/// shapes where that index has to survive bulk removals from the stack, and where an unknown tag
/// name forces the fallback scan.
class StackScopeTrackingTest: XCTestCase {

    func testParagraphAutoClosedByFollowingBlock() throws {
        let doc = try SwiftSoup.parse("<div><p>one<p>two<div>three</div></div>")
        XCTAssertEqual(2, try doc.select("p").size())
        XCTAssertEqual("one", try doc.select("p").first()?.text())
        XCTAssertEqual("three", try doc.select("div div").text())
    }

    func testParagraphInsideButtonScopeIsNotClosedThrough() throws {
        // A <p> inside a <button> must not be closed by a <p> outside it.
        let doc = try SwiftSoup.parse("<p>outer<button><p>inner</button>")
        XCTAssertEqual(2, try doc.select("p").size())
        XCTAssertEqual(1, try doc.select("button p").size())
        XCTAssertEqual("inner", try doc.select("button p").text())
    }

    func testTrackingSurvivesTableSectionsClosingManyElements() throws {
        // Closing a table pops a run of open elements at once.
        let doc = try SwiftSoup.parse("<table><tr><td><p>a<p>b</td></tr></table><p>after")
        XCTAssertEqual(3, try doc.select("p").size())
        XCTAssertEqual("after", try doc.select("body > p").text())
    }

    func testTrackingWithUnknownTagsOnTheStack() throws {
        // Unknown tag names take the fallback path; mixing them with p/button must still be right.
        let doc = try SwiftSoup.parse("<custom-a><p>one<button><custom-b><p>two</custom-b></button></custom-a><p>three")
        XCTAssertEqual(3, try doc.select("p").size())
        XCTAssertEqual("two", try doc.select("button p").text())
    }

    func testDeeplyNestedParagraphsRoundTrip() throws {
        // Repeated open/close at depth is where the stack index is rebuilt most often.
        let html = String(repeating: "<div>", count: 50)
            + String(repeating: "<p>x</p>", count: 200)
            + String(repeating: "</div>", count: 50)
        let doc = try SwiftSoup.parse(html)
        XCTAssertEqual(200, try doc.select("p").size())
        XCTAssertEqual(50, try doc.select("div").size())
    }
}
