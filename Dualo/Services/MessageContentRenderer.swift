//
//  MessageContentRenderer.swift
//  Dualo
//
//  Created by Robert Conover on 8/13/25.
//

import SwiftUI
import Foundation

struct MessageContentRenderer {
    
    enum ContentType: Identifiable, Equatable {
        case text(AttributedString, index: Int)
        case codeBlock(code: String, language: String?, index: Int)
        case thinkingBlock(content: String, index: Int)
        
        var id: String {
            switch self {
            case .text(_, let index):
                return "text_\(index)"
            case .codeBlock(_, _, let index):
                return "code_\(index)"
            case .thinkingBlock(_, let index):
                return "thinking_\(index)"
            }
        }
    }
    
    static func parse(_ content: String) -> [ContentType] {
        var results: [UnindexedContentType] = []
        var currentPosition = content.startIndex
        
        // First, extract <think>...</think> blocks before processing other content
        // Pattern handles both closed tags and unclosed tags (for streaming)
        let thinkingPattern = #"<think>(.*?)(?:</think>|$)"#
        let thinkingRegex = try? NSRegularExpression(pattern: thinkingPattern, options: [.dotMatchesLineSeparators])
        let nsContent = content as NSString
        let thinkingMatches = thinkingRegex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) ?? []
        
        // Process thinking blocks and collect non-thinking content segments
        var nonThinkingSegments: [(String, Range<String.Index>)] = []
        
        for match in thinkingMatches {
            guard let matchRange = Range(match.range, in: content),
                  let thinkingContentRange = Range(match.range(at: 1), in: content) else {
                continue
            }
            
            // Collect text before this thinking block
            if currentPosition < matchRange.lowerBound {
                let beforeText = String(content[currentPosition..<matchRange.lowerBound])
                nonThinkingSegments.append((beforeText, currentPosition..<matchRange.lowerBound))
            }
            
            // Add thinking block if it has content
            let thinkingContent = String(content[thinkingContentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !thinkingContent.isEmpty {
                results.append(.thinkingBlock(content: thinkingContent))
            }
            
            currentPosition = matchRange.upperBound
        }
        
        // Collect remaining text after all thinking blocks
        if currentPosition < content.endIndex {
            let remainingText = String(content[currentPosition...])
            nonThinkingSegments.append((remainingText, currentPosition..<content.endIndex))
        }
        
        // If no thinking blocks found, process entire content
        if thinkingMatches.isEmpty {
            results.append(contentsOf: parseNonThinkingContent(content))
        } else {
            // Process each non-thinking segment
            for (segment, _) in nonThinkingSegments {
                let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedSegment.isEmpty {
                    results.append(contentsOf: parseNonThinkingContent(segment))
                }
            }
        }
        
        if results.isEmpty, let attributedText = parseMarkdown(content) {
            results.append(.text(attributedText))
        }
        
        // Assign unique indices to each content block
        return results.enumerated().map { index, item in
            item.toIndexed(index: index)
        }
    }
    
    /// Internal type without index for parsing, converted to ContentType at the end
    private enum UnindexedContentType {
        case text(AttributedString)
        case codeBlock(code: String, language: String?)
        case thinkingBlock(content: String)
        
        func toIndexed(index: Int) -> ContentType {
            switch self {
            case .text(let content):
                return .text(content, index: index)
            case .codeBlock(let code, let language):
                return .codeBlock(code: code, language: language, index: index)
            case .thinkingBlock(let content):
                return .thinkingBlock(content: content, index: index)
            }
        }
    }
    
    /// Parses content that doesn't contain thinking blocks (handles code blocks and text)
    private static func parseNonThinkingContent(_ content: String) -> [UnindexedContentType] {
        var results: [UnindexedContentType] = []
        var currentPosition = content.startIndex
        
        // Updated pattern to handle various code block formats
        let codeBlockPattern = #"```(\w*)\r?\n?(.*?)```"#
        let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: [.dotMatchesLineSeparators])
        let nsContent = content as NSString
        let matches = regex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) ?? []
        
        for match in matches {
            guard let matchRange = Range(match.range, in: content),
                  let codeRange = Range(match.range(at: 2), in: content) else {
                continue
            }
            
            if currentPosition < matchRange.lowerBound {
                let textContent = String(content[currentPosition..<matchRange.lowerBound])
                if let attributedText = parseMarkdown(textContent), !attributedText.characters.isEmpty {
                    results.append(.text(attributedText))
                }
            }
            
            let languageRange = Range(match.range(at: 1), in: content)
            
            let language = languageRange.flatMap { String(content[$0]).isEmpty ? nil : String(content[$0]) }
            let code = String(content[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            results.append(.codeBlock(code: code, language: language))
            currentPosition = matchRange.upperBound
        }
        
        // If no code blocks found, check for code-like patterns
        if matches.isEmpty {
            let lines = content.components(separatedBy: .newlines)
            
            // Special case: if it's just a single line that looks like code, treat it as a code block
            if lines.count == 1 {
                let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if isCodeLike(trimmedContent) {
                    let language = detectLanguage(from: trimmedContent)
                    results.append(.codeBlock(code: trimmedContent, language: language))
                    return results
                }
            }
            
            var isProcessingCode = false
            var codeLines: [String] = []
            var textBuffer = ""
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                // Check if line looks like code
                if isCodeLike(trimmedLine) {
                    if !textBuffer.isEmpty && !isProcessingCode {
                        if let attributedText = parseMarkdown(textBuffer), !attributedText.characters.isEmpty {
                            results.append(.text(attributedText))
                        }
                        textBuffer = ""
                    }
                    isProcessingCode = true
                    codeLines.append(line)
                } else if isProcessingCode && (line.isEmpty || !line.trimmingCharacters(in: .whitespaces).isEmpty) {
                    // End of code block
                    if !codeLines.isEmpty {
                        let code = codeLines.joined(separator: "\n")
                        let language = detectLanguage(from: code)
                        results.append(.codeBlock(code: code, language: language))
                        codeLines = []
                    }
                    isProcessingCode = false
                    if !line.isEmpty {
                        textBuffer += line + "\n"
                    }
                } else {
                    if isProcessingCode {
                        codeLines.append(line)
                    } else {
                        textBuffer += line + "\n"
                    }
                }
            }
            
            // Handle remaining content
            if !codeLines.isEmpty {
                let code = codeLines.joined(separator: "\n")
                let language = detectLanguage(from: code)
                results.append(.codeBlock(code: code, language: language))
            } else if !textBuffer.isEmpty {
                if let attributedText = parseMarkdown(textBuffer), !attributedText.characters.isEmpty {
                    results.append(.text(attributedText))
                }
            }
        } else {
            // Handle remaining text after code blocks
            if currentPosition < content.endIndex {
                let remainingText = String(content[currentPosition...])
                if let attributedText = parseMarkdown(remainingText), !attributedText.characters.isEmpty {
                    results.append(.text(attributedText))
                }
            }
        }
        
        return results
    }
    
    private static func isCodeLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for common code patterns
        return trimmed.hasPrefix("print(") || trimmed.hasPrefix("def ") ||
               trimmed.hasPrefix("function ") || trimmed.hasPrefix("var ") ||
               trimmed.hasPrefix("let ") || trimmed.hasPrefix("const ") ||
               trimmed.hasPrefix("import ") || trimmed.hasPrefix("class ") ||
               trimmed.hasPrefix("func ") || trimmed.hasPrefix("struct ") ||
               trimmed.hasPrefix("//") || trimmed.hasPrefix("#") ||
               trimmed.hasPrefix("/*") || trimmed.hasPrefix("*/") ||
               trimmed.hasPrefix("if ") || trimmed.hasPrefix("for ") ||
               trimmed.hasPrefix("while ") || trimmed.hasPrefix("return ") ||
               (trimmed.contains("(") && trimmed.contains(")") && 
                (trimmed.contains("print") || trimmed.contains("console.log") || 
                 trimmed.contains("printf") || trimmed.contains("echo"))) ||
               (trimmed.hasSuffix(";") && trimmed.count > 3) ||
               (trimmed.contains("=") && trimmed.contains("(") && trimmed.contains(")"))
    }
    
    private static func detectLanguage(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.contains("print(") && trimmed.contains(")") {
            return "python"
        } else if trimmed.contains("func ") || trimmed.contains("var ") || trimmed.contains("let ") {
            return "swift"
        } else if trimmed.contains("function ") || trimmed.contains("const ") || trimmed.contains("=>") {
            return "javascript"
        } else if trimmed.contains("console.log") {
            return "javascript"
        } else if trimmed.contains("printf") || trimmed.contains("#include") {
            return "c"
        }
        
        return nil
    }
    
    static func parseMarkdown(_ text: String) -> AttributedString? {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            
            var attributedString = try AttributedString(markdown: text, options: options)
            
            for run in attributedString.runs {
                var container = AttributeContainer()
                
                if let intent = run.inlinePresentationIntent {
                    if intent.contains(.stronglyEmphasized) {
                        container.font = .body.bold()
                    }
                    if intent.contains(.emphasized) {
                        container.font = .body.italic()
                    }
                    if intent.contains(.code) {
                        container.font = .system(.body, design: .monospaced)
                        container.backgroundColor = Color(UIColor.secondarySystemBackground)
                        container.foregroundColor = Color.primary
                    }
                }
                
                if run.link != nil {
                    container.foregroundColor = .blue
                    container.underlineStyle = .single
                }
                
                attributedString[run.range].mergeAttributes(container)
            }
            
            return attributedString
        } catch {
            return AttributedString(text)
        }
    }
}