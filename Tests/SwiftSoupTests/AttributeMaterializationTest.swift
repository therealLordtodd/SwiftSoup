//
//  AttributeMaterializationTest.swift
//  SwiftSoup
//

import XCTest
@testable import SwiftSoup

class AttributeMaterializationTest: XCTestCase {

    private func tag(attributeCount n: Int) -> String {
        var html = "<div"
        for i in 0..<n { html += " a\(i)=\"v\(i)\"" }
        return html + ">x</div>"
    }

    /// Materializing an element's attributes must build the key index when the element will hold
    /// enough attributes to warrant one -- counting the pending attributes, which are all of them
    /// at this point. Without that, materialization deduplicates with a linear scan per attribute.
    func testMaterializationBuildsKeyIndexFromPendingAttributes() throws {
        let count = Attributes.keyIndexThreshold * 4
        let doc = try SwiftSoup.parse(tag(attributeCount: count))
        let element = try XCTUnwrap(try doc.select("div").first())
        let attributes = try XCTUnwrap(element.getAttributes())

        XCTAssertEqual(count, attributes.size())
        XCTAssertFalse(attributes.keyIndexDirty)
        XCTAssertEqual(count, try XCTUnwrap(attributes.keyIndex).count)
    }

    /// Below the threshold the linear path is still used, exactly as before.
    func testSmallAttributeCountDoesNotBuildKeyIndex() throws {
        let count = Attributes.keyIndexThreshold - 1
        let doc = try SwiftSoup.parse(tag(attributeCount: count))
        let element = try XCTUnwrap(try doc.select("div").first())
        let attributes = try XCTUnwrap(element.getAttributes())

        XCTAssertEqual(count, attributes.size())
        XCTAssertNil(attributes.keyIndex)
    }

    func testAttributesAreStillDeduplicatedAndOrdered() throws {
        // Repeated keys must collapse to the first position, keeping the first value, whether or
        // not the key index is in play.
        for count in [Attributes.keyIndexThreshold - 1, Attributes.keyIndexThreshold * 4] {
            var html = "<div a=\"1\" b=\"2\" a=\"3\""
            for i in 0..<count { html += " k\(i)=\"\(i)\"" }
            html += ">x</div>"

            let doc = try SwiftSoup.parse(html)
            let element = try XCTUnwrap(try doc.select("div").first())
            XCTAssertEqual("1", try element.attr("a"), "count=\(count)")
            XCTAssertEqual("2", try element.attr("b"), "count=\(count)")
            XCTAssertEqual(count + 2, element.getAttributes()?.size(), "count=\(count)")
        }
    }
}
