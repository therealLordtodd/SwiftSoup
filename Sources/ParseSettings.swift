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

    /**
     The value of ``maxTreeDepth`` that disables the tree depth limit. This is the default,
     so that parse behaviour is unchanged unless a limit is explicitly requested.
     */
    public static let unlimitedTreeDepth: Int = Int.max
    
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
    }

    public init(_ tag: Bool, _ attribute: Bool, _ trackSourceRanges: Bool) {
        preserveTagCase = tag
        preserveAttributeCase = attribute
        self.trackSourceRanges = trackSourceRanges
        trackAttributes = true
        maxTreeDepth = ParseSettings.unlimitedTreeDepth
    }

    public init(_ tag: Bool, _ attribute: Bool, _ trackSourceRanges: Bool, _ trackAttributes: Bool) {
        preserveTagCase = tag
        preserveAttributeCase = attribute
        self.trackSourceRanges = trackSourceRanges
        self.trackAttributes = trackAttributes
        maxTreeDepth = ParseSettings.unlimitedTreeDepth
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
        return ParseSettings(preserveTagCase, preserveAttributeCase, trackSourceRanges, trackAttributes, depth)
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
