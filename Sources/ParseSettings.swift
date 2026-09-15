//
//  ParseSettings.swift
//  SwiftSoup
//
//  Created by Nabil Chatbi on 14/10/16.
//

import Foundation

open class ParseSettings: @unchecked Sendable {
    /**
     * HTML default settings: both tag and attribute names are lower-cased during parsing.
     */
    public static let htmlDefault: ParseSettings = ParseSettings(false, false)
    /**
     * Preserve both tag and attribute case.
     */
    public static let preserveCase: ParseSettings = ParseSettings(true, true)

    private let preserveTagCase: Bool
    private let preserveAttributeCase: Bool
    private let trackSourceRanges: Bool
    private let trackAttributes: Bool
    private let maxTreeDepth: Int
    private let maxParseWork: Int

    /**
     The value of ``maxTreeDepth`` that disables the tree depth limit. This is the default,
     so that parse behaviour is unchanged unless a limit is explicitly requested.
     */
    public static let unlimitedTreeDepth: Int = Int.max

    /**
     The value of ``maxParseWork`` that disables the parse work budget. This is the default, so
     that parse behaviour is unchanged unless a budget is explicitly requested.
     */
    public static let unlimitedParseWork: Int = Int.max
    
    @usableFromInline
    internal static let defaultTrackSourceRanges: Bool = true

    /**
     Define parse settings.
     - parameter tag: preserve tag case?
     - parameter attribute: preserve attribute name case?
     */
    public init(_ tag: Bool, _ attribute: Bool) {
        preserveTagCase = tag
        preserveAttributeCase = attribute
        trackSourceRanges = ParseSettings.defaultTrackSourceRanges
        trackAttributes = true
        maxTreeDepth = ParseSettings.unlimitedTreeDepth
        maxParseWork = ParseSettings.unlimitedParseWork
    }

    public init(_ tag: Bool, _ attribute: Bool, _ trackSourceRanges: Bool) {
        preserveTagCase = tag
        preserveAttributeCase = attribute
        self.trackSourceRanges = trackSourceRanges
        trackAttributes = true
        maxTreeDepth = ParseSettings.unlimitedTreeDepth
        maxParseWork = ParseSettings.unlimitedParseWork
    }

    public init(_ tag: Bool, _ attribute: Bool, _ trackSourceRanges: Bool, _ trackAttributes: Bool) {
        preserveTagCase = tag
        preserveAttributeCase = attribute
        self.trackSourceRanges = trackSourceRanges
        self.trackAttributes = trackAttributes
        maxTreeDepth = ParseSettings.unlimitedTreeDepth
        maxParseWork = ParseSettings.unlimitedParseWork
    }

    /**
     Define parse settings, including a maximum tree depth.
     - parameter tag: preserve tag case?
     - parameter attribute: preserve attribute name case?
     - parameter trackSourceRanges: record source ranges on parsed nodes?
     - parameter trackAttributes: retain attributes on parsed elements?
     - parameter maxTreeDepth: the maximum nesting depth of any element in the parsed
     tree, counting parser-created shells (`html`, `head`, `body`, implied `tbody`) as the finished
     tree contains them. A parse that would attach an element deeper than this throws
     `Exception.Error(type: .TreeDepthExceeded, ...)`.
     Use ``unlimitedTreeDepth`` (the default) for no limit.
     */
    public init(_ tag: Bool, _ attribute: Bool, _ trackSourceRanges: Bool, _ trackAttributes: Bool, _ maxTreeDepth: Int) {
        preserveTagCase = tag
        preserveAttributeCase = attribute
        self.trackSourceRanges = trackSourceRanges
        self.trackAttributes = trackAttributes
        self.maxTreeDepth = maxTreeDepth
        maxParseWork = ParseSettings.unlimitedParseWork
    }

    /**
     Define parse settings, including a maximum tree depth and a parse work budget.
     - parameter tag: preserve tag case?
     - parameter attribute: preserve attribute name case?
     - parameter trackSourceRanges: record source ranges on parsed nodes?
     - parameter trackAttributes: retain attributes on parsed elements?
     - parameter maxTreeDepth: see ``maximumTreeDepth()``.
     - parameter maxParseWork: see ``maximumParseWork()``.
     */
    public init(_ tag: Bool, _ attribute: Bool, _ trackSourceRanges: Bool, _ trackAttributes: Bool, _ maxTreeDepth: Int, _ maxParseWork: Int) {
        preserveTagCase = tag
        preserveAttributeCase = attribute
        self.trackSourceRanges = trackSourceRanges
        self.trackAttributes = trackAttributes
        self.maxTreeDepth = maxTreeDepth
        self.maxParseWork = maxParseWork
    }

    @inline(__always)
    internal func preservesTagCase() -> Bool {
        return preserveTagCase
    }

    @inline(__always)
    internal func preservesAttributeCase() -> Bool {
        return preserveAttributeCase
    }

    @inline(__always)
    internal func tracksSourceRanges() -> Bool {
        return trackSourceRanges
    }

    @inline(__always)
    internal func tracksAttributes() -> Bool {
        return trackAttributes
    }

    /**
     The maximum nesting depth of any element in the parsed tree, counting parser-created shells
     (`html`, `head`, `body`, implied `tbody`) as the finished tree contains them. A parse that
     would attach an element deeper than this throws
     `Exception.Error(type: .TreeDepthExceeded, ...)`. ``unlimitedTreeDepth`` means no limit.
     */
    @inline(__always)
    public func maximumTreeDepth() -> Int {
        return maxTreeDepth
    }

    /**
     Returns a copy of these settings with the given maximum tree depth.

     - parameter depth: the maximum nesting depth of any element in the parsed
     tree, counting parser-created shells (`html`, `head`, `body`, implied `tbody`) as the finished
     tree contains them. A parse that would attach an element deeper than this throws
     `Exception.Error(type: .TreeDepthExceeded, ...)`.
     Pass ``unlimitedTreeDepth`` for no limit.
     - returns: a new `ParseSettings`; the receiver is not modified.
     */
    open func withMaxTreeDepth(_ depth: Int) -> ParseSettings {
        return ParseSettings(preserveTagCase, preserveAttributeCase, trackSourceRanges, trackAttributes, depth, maxParseWork)
    }

    /**
     A budget for the total work a parse may do, in work units, or ``unlimitedParseWork`` (the
     default) for no budget. A parse that exceeds it throws
     `Exception.Error(type: .ParseBudgetExceeded, ...)`.

     A **work unit** is one of two things, and the budget counts both:

     1. One node attached to the tree -- element, text, comment or doctype.
     2. One entry examined on the stack of open elements by a scan: the scope tests
        (`inScope`, `inButtonScope`, `inTableScope`, `inSelectScope`, `inListItemScope`), the
        searches that close or clear elements (`popStackToClose`, `clearStackToContext`,
        `popStackToBefore`), and the lookups that locate an element on the stack.

     Both are counted because neither bounds a parse on its own. Nodes alone miss that a scan can
     cost as much as the stack is deep, which is what makes a deeply nested document expensive out
     of proportion to its size; scans alone miss a large flat document. Counting them together
     tracks the real cost closely enough to size a budget from a measured corpus: parse a
     representative sample, read the work it used, and set the budget some multiple above it.

     The count is deterministic -- it depends only on the input and the settings, never on machine
     speed or load -- so the same document always succeeds or fails the same way. That is the point
     of a work budget rather than a timeout.
     */
    @inline(__always)
    public func maximumParseWork() -> Int {
        return maxParseWork
    }

    /**
     Returns a copy of these settings with the given parse work budget.

     - parameter work: the budget in work units (see ``maximumParseWork()``), or
     ``unlimitedParseWork`` for no budget.
     - returns: a new `ParseSettings`; the receiver is not modified.
     */
    open func withMaxParseWork(_ work: Int) -> ParseSettings {
        return ParseSettings(preserveTagCase, preserveAttributeCase, trackSourceRanges, trackAttributes, maxTreeDepth, work)
    }

    open func normalizeTag(_ name: [UInt8]) -> [UInt8] {
        var name = name.trim()
        if (!preserveTagCase) {
            name = name.lowercased()
        }
        return name
    }

    @usableFromInline
    internal func normalizeTag(_ name: ByteSlice) -> ByteSlice {
        var name = name.trim()
        if (!preserveTagCase) {
            name = name.lowercased()
        }
        return name
    }
    
    open func normalizeTag(_ name: String) -> String {
        return String(decoding: normalizeTag(name.utf8Array), as: UTF8.self)
    }

    open func normalizeAttribute(_ name: [UInt8]) -> [UInt8] {
        var name = name.trim()
        if (!preserveAttributeCase) {
            name = name.lowercased()
        }
        return name
    }

    @usableFromInline
    internal func normalizeAttribute(_ name: ByteSlice) -> ByteSlice {
        var name = name.trim()
        if (!preserveAttributeCase) {
            name = name.lowercased()
        }
        return name
    }
    
    open func normalizeAttribute(_ name: String) -> String {
        return String(decoding: normalizeAttribute(name.utf8Array), as: UTF8.self)
    }

    open func normalizeAttributes(_ attributes: Attributes) throws -> Attributes {
        if (!preserveAttributeCase) {
            attributes.lowercaseAllKeys()
        }
        return attributes
    }

}
