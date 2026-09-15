//
//  TreeBuilder.swift
//  SwiftSoup
//
//  Created by Nabil Chatbi on 24/10/16.
//

import Foundation

public class TreeBuilder {
    public var reader: CharacterReader
    var tokeniser: Tokeniser
    public var doc: Document // current doc we are building into
    public var stack: Array<Element> // the stack of open elements
    public var baseUri: [UInt8] // current base uri, for creating new elements
    public var currentToken: Token? // currentToken is used only for error tracking.
    public var errors: ParseErrorList // null when not tracking errors
    public var settings: ParseSettings
    public var tracksSourceRanges: Bool = false
    public var tracksErrors: Bool = false
    /// Cached from `settings.maximumTreeDepth()` at parse start; `Int.max` means unlimited.
    /// Enforced by `enforceTreeDepth` against the ancestry depth of each node as it is attached,
    /// so parser-created structure (`html`/`head`/`body` shells, implied `tbody`, ...) counts
    /// exactly as authored elements do.
    public var maxTreeDepth: Int = ParseSettings.unlimitedTreeDepth
    /// Cached from `settings.maximumParseWork()` at parse start; `Int.max` means unbudgeted.
    public var maxParseWork: Int = ParseSettings.unlimitedParseWork
    /// Work units consumed by the parse in progress. See `ParseSettings.maximumParseWork()`.
    public var parseWork: Int = 0
    @usableFromInline
    var pendingAttributeElements: [Element] = []
    
    private let start: Token.StartTag = Token.StartTag() // start tag to process
    private let end: Token.EndTag  = Token.EndTag()
    
    /// Bulk-build suppression flag
    @usableFromInline
    var isBulkBuilding: Bool = false
    
    
    public func defaultSettings() -> ParseSettings {preconditionFailure("This method must be overridden")}
    
    public init() {
        doc =  Document([])
        reader = CharacterReader([])
        stack = Array<Element>()
        baseUri = []
        errors = ParseErrorList(0, 0)
        settings = ParseSettings(false, false)
        maxTreeDepth = settings.maximumTreeDepth()
        maxParseWork = settings.maximumParseWork()
        tokeniser = Tokeniser(reader, nil, settings)
    }
    
    @inline(__always)
    func beginBulkAppend() {
        isBulkBuilding = true
    }
    
    @inline(__always)
    func endBulkAppend() {
        isBulkBuilding = false
    }
    
    public func initialiseParse(_ input: [UInt8], _ baseUri: [UInt8], _ errors: ParseErrorList, _ settings: ParseSettings) {
        doc = Document(baseUri)
        // Anchor the document to this parse. Everything that depends on the parse rather than on
        // the entry point -- the work budget in particular -- reaches the tree builder through it,
        // so it has to be set wherever a parse starts, not only on the document route.
        doc.treeBuilder = self
        tracksSourceRanges = settings.tracksSourceRanges()
        if tracksSourceRanges {
            doc.sourceBuffer = SourceBuffer(input)
        } else {
            doc.sourceBuffer = nil
        }
        doc.parsedAsXml = false
        self.settings = settings
        maxTreeDepth = settings.maximumTreeDepth()
        maxParseWork = settings.maximumParseWork()
        parseWork = 0
        let parseBuffer: [UInt8]
        if tracksSourceRanges, let sourceBuffer = doc.sourceBuffer {
            parseBuffer = sourceBuffer.bytes
        } else {
            parseBuffer = input
        }
        reader = CharacterReader(parseBuffer)
        self.errors = errors
        tracksErrors = errors.getMaxSize() > 0
        tokeniser = Tokeniser(reader, tracksErrors ? errors : nil, settings)
        stack = Array<Element>()
        self.baseUri = baseUri
        pendingAttributeElements.removeAll(keepingCapacity: true)
    }

    public func initialiseParse(_ input: UnsafeBufferPointer<UInt8>, owner: AnyObject?, _ baseUri: [UInt8], _ errors: ParseErrorList, _ settings: ParseSettings) {
        doc = Document(baseUri)
        // Anchor the document to this parse. Everything that depends on the parse rather than on
        // the entry point -- the work budget in particular -- reaches the tree builder through it,
        // so it has to be set wherever a parse starts, not only on the document route.
        doc.treeBuilder = self
        tracksSourceRanges = settings.tracksSourceRanges()
        if tracksSourceRanges {
            let copied = Array(input)
            doc.sourceBuffer = SourceBuffer(copied)
            reader = CharacterReader(copied)
        } else {
            doc.sourceBuffer = nil
            reader = CharacterReader(input, owner: owner)
        }
        doc.parsedAsXml = false
        self.settings = settings
        maxTreeDepth = settings.maximumTreeDepth()
        maxParseWork = settings.maximumParseWork()
        parseWork = 0
        self.errors = errors
        tracksErrors = errors.getMaxSize() > 0
        tokeniser = Tokeniser(reader, tracksErrors ? errors : nil, settings)
        stack = Array<Element>()
        self.baseUri = baseUri
        pendingAttributeElements.removeAll(keepingCapacity: true)
    }
    
    func parse(_ input: [UInt8], _ baseUri: [UInt8],
               _ errors: ParseErrorList,
               _ settings: ParseSettings) throws -> Document {
        // Associate builder for node-level checks
        doc.treeBuilder = self
        
        // Suppress per-append index invalidation; rebuild once at end
        beginBulkAppend()
        defer { endBulkAppend() }
        
        initialiseParse(input, baseUri, errors, settings)
        try runParser()
        if !tracksSourceRanges, !pendingAttributeElements.isEmpty {
            for element in pendingAttributeElements {
                element.attributes?.ensureMaterialized()
            }
            pendingAttributeElements.removeAll(keepingCapacity: true)
        }
        return doc
    }

    func parse(_ input: UnsafeBufferPointer<UInt8>, owner: AnyObject?, _ baseUri: [UInt8],
               _ errors: ParseErrorList,
               _ settings: ParseSettings) throws -> Document {
        doc.treeBuilder = self
        beginBulkAppend()
        defer { endBulkAppend() }

        initialiseParse(input, owner: owner, baseUri, errors, settings)
        try runParser()
        if !tracksSourceRanges, !pendingAttributeElements.isEmpty {
            for element in pendingAttributeElements {
                element.attributes?.ensureMaterialized()
            }
            pendingAttributeElements.removeAll(keepingCapacity: true)
        }
        return doc
    }
    
    @inline(__always)
    func registerPendingAttributes(_ element: Element) {
        guard !tracksSourceRanges else { return }
        if let attributes = element.attributes,
           attributes.pendingAttributesCount > 0 {
            pendingAttributeElements.append(element)
        }
    }
    
    public func runParser() throws {
        while (true) {
            let token: Token = try tokeniser.read()
            try process(token)
            try chargeParseWork(0) // enforce scan work recorded by this token
            if (token.type == Token.TokenType.EOF) {
                break
            }
        }
    }

    @discardableResult
    @inline(__always)
    public func process(_ token: Token)throws->Bool {preconditionFailure("This method must be overridden")}
    
    @discardableResult
    @inline(__always)
    public func processStartTag(_ name: [UInt8]) throws -> Bool {
        if (currentToken === start) { // don't recycle an in-use token
            return try process(Token.StartTag().name(name))
        }
        return try process(start.reset().name(name))
    }
    
    @discardableResult
    @inline(__always)
    public func processStartTag(_ name: String) throws -> Bool {
        return try processStartTag(name.utf8Array)
    }
    
    @discardableResult
    @inline(__always)
    public func processStartTag(_ name: [UInt8], _ attrs: Attributes) throws -> Bool {
        if (currentToken === start) { // don't recycle an in-use token
            return try process(Token.StartTag().nameAttr(name, attrs))
        }
        start.reset()
        start.nameAttr(name, attrs)
        return try process(start)
    }
    
    @discardableResult
    @inline(__always)
    public func processStartTag(_ name: String, _ attrs: Attributes) throws -> Bool {
        return try processStartTag(name.utf8Array, attrs)
    }
    
    @discardableResult
    @inline(__always)
    public func processEndTag(_ name: [UInt8]) throws -> Bool {
        if (currentToken === end) { // don't recycle an in-use token
            return try process(Token.EndTag().name(name))
        }
        
        return try process(end.reset().name(name))
    }

    
    @discardableResult
    @inline(__always)
    public func processEndTag(_ name: String) throws -> Bool {
        return try processEndTag(name.utf8Array)
    }
    
    @inline(__always)
    public func currentElement() -> Element? {
        return stack.last
    }

    /// `true` when a tree depth limit is in force. Guard depth bookkeeping behind this so an
    /// unlimited parse (the default) pays nothing beyond one integer comparison.
    @inlinable
    public var isDepthLimited: Bool {
        return maxTreeDepth != ParseSettings.unlimitedTreeDepth
    }

    /// `true` when a parse work budget is in force. Guard the accounting behind this so an
    /// unbudgeted parse (the default) pays nothing beyond one integer comparison.
    @inlinable
    public var isWorkLimited: Bool {
        return maxParseWork != ParseSettings.unlimitedParseWork
    }

    /// Record stack-scan work. Non-throwing: the budget is enforced at the next checkpoint
    /// (`chargeParseWork`, called per attached node and once per token), so the scan helpers that
    /// are not `throws` today do not have to become so. Overshoot is bounded by one token's work.
    @inlinable
    @inline(__always)
    public func countStackWork(_ units: Int) {
        if maxParseWork == ParseSettings.unlimitedParseWork { return }
        parseWork &+= units
    }

    /// Charge `units` of work to the budget. See `ParseSettings.maximumParseWork()` for what a
    /// unit is. Cheap when unbudgeted: one comparison.
    @inlinable
    @inline(__always)
    public func chargeParseWork(_ units: Int) throws {
        if maxParseWork == ParseSettings.unlimitedParseWork { return }
        parseWork &+= units
        if parseWork > maxParseWork {
            throw Exception.Error(type: .ParseBudgetExceeded,
                                  Message: "Parse work budget of \(maxParseWork) units exceeded")
        }
    }

    /**
     Enforces `settings.maximumTreeDepth()` against the *resulting ancestry depth* of a node that is
     about to be attached under `parent`.

     Depth convention: the depth of a node is the number of `Element` ancestors on the path from the
     owning `Document` down to and including the node itself. The `Document` is not counted (even
     though `Document` subclasses `Element`), so the `html` element of a parsed document -- or the
     `html` shell the fragment parser creates -- has depth 1. A limit of 512 therefore permits 512
     nested elements including every parser-created shell (`html`, `head`, `body`, implied `tbody`,
     ...), exactly as they appear in the finished tree.

     This is deliberately *not* a check on `stack.count`. The stack of open elements can be much
     shallower than the tree: the HTML `</form>` rule removes a form from the stack without popping
     its open descendants, so `<form><div></form>` repeated N times builds 2N levels of DOM while
     the stack never exceeds N+1.

     - parameter parent: the node the new content will be attached under.
     - parameter addedHeight: the height the attached content adds below `parent`: 1 for a single
     new element, 0 for a text or comment node (which cannot have element children), or the height
     of a moved subtree when reparenting.

     The ancestor walk aborts as soon as the running depth exceeds the limit, so the check is
     O(maxTreeDepth) and is skipped entirely (a single integer comparison) when no limit is set.
     */
    @inlinable
    public func enforceTreeDepth(attachingUnder parent: Node, addedHeight: Int) throws {
        let limit = maxTreeDepth
        if limit == ParseSettings.unlimitedTreeDepth { return }
        var depth = addedHeight
        if depth > limit { throw TreeBuilder.treeDepthError(limit) }
        var cursor: Node? = parent
        while let node = cursor {
            if node is Document { break }
            depth += 1
            if depth > limit { throw TreeBuilder.treeDepthError(limit) }
            cursor = node.parentNode
        }
    }

    @usableFromInline
    static func treeDepthError(_ limit: Int) -> Exception {
        return Exception.Error(type: .TreeDepthExceeded,
                               Message: "Tree depth limit of \(limit) exceeded while parsing")
    }

    /**
     The height of `node`'s subtree measured in elements: 1 for an element with no element children.
     Returns as soon as the measured height exceeds `cap`, so the walk stays bounded.
     */
    @usableFromInline
    func subtreeHeight(_ node: Node, cappedAt cap: Int) -> Int {
        guard node is Element else { return 0 }
        var height = 0
        var level: [Node] = [node]
        while !level.isEmpty {
            height += 1
            if height > cap { return height }
            var next: [Node] = []
            for item in level {
                guard let element = item as? Element else { continue }
                for child in element.childNodes where child is Element {
                    next.append(child)
                }
            }
            level = next
        }
        return height
    }
}
