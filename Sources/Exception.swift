//
//  Exception.swift
//  SwifSoup
//
//  Created by Nabil Chatbi on 02/10/16.
//

import Foundation

public enum ExceptionType: Sendable {
    case IllegalArgumentException
    case IOException
    case XmlDeclaration
    case MalformedURLException
    case CloneNotSupportedException
    case SelectorParseException
    /// Thrown when a parse would nest elements deeper than the configured
    /// `ParseSettings.maxTreeDepth` limit.
    case TreeDepthExceeded
    /// Thrown when a parse does more work than the configured
    /// `ParseSettings.maxParseWork` budget allows.
    case ParseBudgetExceeded
}

public enum Exception: Error {
    case Error(type:ExceptionType, Message: String)
}
