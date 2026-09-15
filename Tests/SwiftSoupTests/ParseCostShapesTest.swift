//
//  ParseCostShapesTest.swift
//  SwiftSoup
//

import XCTest
@testable import SwiftSoup

/// Shapes whose parse cost has gone quadratic before. Two guards per shape: the time roughly
/// doubles when the input doubles, and the work the parse charges itself stays in proportion to the
/// time it takes. The second is the one that matters -- a scan nobody charges shows up as time
/// without units, which is exactly how the regressions here were missed.
class ParseCostShapesTest: XCTestCase {

    private func formattingBlocks(_ n: Int) -> String { String(repeating: "<b><p>", count: n) }
    private func italicDivs(_ n: Int) -> String { String(repeating: "<i><div>", count: n) }
    private func anchorLists(_ n: Int) -> String { String(repeating: "<a href=#><ul><li>", count: n) }
    private func flatParagraphs(_ n: Int) -> String { String(repeating: "<p>x</p>", count: n) }

    private let noRanges = ParseSettings(false, false, false)

    private func measure(_ html: String) throws -> (seconds: Double, units: Int) {
        let parser = Parser.htmlParser()
        parser.settings(ParseSettings(false, false, false, true,
                                      ParseSettings.unlimitedTreeDepth, Int.max - 1))
        let start = Date()
        _ = try parser.parseInput(html, "")
        return (Date().timeIntervalSince(start), parser.getTreeBuilder().parseWork)
    }

    /// Doubling the input must not much more than double the time.
    private func assertScalesLinearly(_ name: String,
                                      _ make: (Int) -> String,
                                      base: Int,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) throws {
        _ = try measure(make(base))  // warm
        let small = try measure(make(base))
        let large = try measure(make(base * 2))
        // Generous: quadratic would be ~4x, and has been ~4x every time this broke.
        let ratio = large.seconds / max(small.seconds, 0.0005)
        XCTAssertLessThan(ratio, 2.8,
                          "\(name): \(base) took \(small.seconds)s, \(base * 2) took \(large.seconds)s",
                          file: file, line: line)
    }

    func testFormattingThenBlockScalesLinearly() throws {
        try assertScalesLinearly("<b><p>", formattingBlocks, base: 4_000)
    }

    /// `<i><div>` is quadratic in SwiftSoup 2.13.9 as released -- 2000/4000/8000 repetitions take
    /// 0.105 / 0.405 / 1.651 s on stock, four times the time for twice the input -- and nothing in
    /// this series changes that either way. It is pinned here so it cannot get worse, not because
    /// it is acceptable. The cost is inside the adoption agency and is worth fixing upstream on its
    /// own; see also `testWorkIsChargedAtAComparableRateAcrossShapes`, which records that the work
    /// budget cannot yet see this particular loop.
    func testItalicThenDivIsNoWorseThanItsKnownQuadratic() throws {
        _ = try measure(italicDivs(4_000))
        let small = try measure(italicDivs(4_000))
        let large = try measure(italicDivs(8_000))
        let ratio = large.seconds / max(small.seconds, 0.0005)
        XCTAssertLessThan(ratio, 5.0,
                          "<i><div> got worse than its known quadratic: "
                          + "4000 took \(small.seconds)s, 8000 took \(large.seconds)s")
    }

    func testAnchorThenListScalesLinearly() throws {
        try assertScalesLinearly("<a href=#><ul><li>", anchorLists, base: 3_000)
    }

    /// The parse must charge itself work at a rate in the same ballpark as a shape known to be
    /// fully charged. A loop the budget cannot see burns time without units and drags the rate
    /// down -- on the regression this test was written for it fell to roughly 188 units per second
    /// against millions for ordinary content.
    func testWorkIsChargedAtAComparableRateAcrossShapes() throws {
        _ = try measure(flatParagraphs(2_000))  // warm

        let flat = try measure(flatParagraphs(20_000))
        let flatRate = Double(flat.units) / max(flat.seconds, 0.0005)

        // `<i><div>` is deliberately absent. It exercises a loop in the adoption agency that the
        // budget does not yet charge -- it bills about 25,000 units per second against roughly a
        // million for the shapes below -- and that gap is recorded rather than papered over. Adding
        // it here once the loop is charged is the test that would prove the fix.
        for (name, html) in [("<b><p>", formattingBlocks(6_000)),
                             ("<a href=#><ul><li>", anchorLists(4_000))] {
            let measured = try measure(html)
            let rate = Double(measured.units) / max(measured.seconds, 0.0005)
            XCTAssertGreaterThan(rate, flatRate / 10,
                                 "\(name) charged \(Int(rate)) units/s against \(Int(flatRate)) for flat content; "
                                 + "a loop the budget cannot see is burning time")
        }
    }
}
