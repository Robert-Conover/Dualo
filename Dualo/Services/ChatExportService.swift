//
//  ChatExportService.swift
//  Dualo
//
//  Created by Robert Conover on 8/13/25.
//

import Foundation
import UIKit
import SwiftUI

class ChatExportService {
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
    
    func makeMarkdown(for conversation: Conversation) -> Data {
        var markdown = "# \(conversation.title)\n\n"
        
        for message in conversation.messages {
            let role = message.role == Message.Role.user ? "User" : "Assistant"
            let timestamp = dateFormatter.string(from: message.timestamp)
            
            markdown += "**\(role)** (\(timestamp)):\n"
            markdown += "\(message.content)\n\n"
        }
        
        return markdown.data(using: .utf8) ?? Data()
    }
    
    func makeText(for conversation: Conversation) -> Data {
        var text = "\(conversation.title)\n\n"
        
        for message in conversation.messages {
            let role = message.role == Message.Role.user ? "User" : "Assistant"
            let timestamp = dateFormatter.string(from: message.timestamp)
            
            text += "\(role) (\(timestamp)):\n"
            text += "\(message.content)\n\n"
        }
        
        return text.data(using: .utf8) ?? Data()
    }
    
    @MainActor
    func makePDF(for conversation: Conversation) async throws -> Data {
        let pageSize = CGSize(width: 612, height: 792) // US Letter size in points
        let margin: CGFloat = 50
        let contentWidth = pageSize.width - (margin * 2)
        
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        
        return pdfRenderer.pdfData { context in
            // Get the graphics context (currently unused but available for future enhancements)
            let _ = context.cgContext
            
            context.beginPage()
            
            var currentY: CGFloat = margin
            let pageBottom = pageSize.height - margin - 40 // Leave room for page number
            
            // Title attributes - using black color explicitly
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            
            // Message header attributes (role and timestamp)
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            
            // Message content attributes
            let contentAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray
            ]
            
            // Footer attributes
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.gray
            ]
            
            // Draw title
            let titleString = NSAttributedString(string: conversation.title, attributes: titleAttributes)
            let titleSize = titleString.boundingRect(
                with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            titleString.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: titleSize.height))
            currentY += titleSize.height + 20
            
            // Draw messages
            var pageNumber = 1
            
            for message in conversation.messages {
                let role = message.role == Message.Role.user ? "User" : "Assistant"
                let timestamp = dateFormatter.string(from: message.timestamp)
                let header = "\(role) (\(timestamp)):"
                
                let headerString = NSAttributedString(string: header, attributes: headerAttributes)
                let headerSize = headerString.boundingRect(
                    with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                
                // Split long content into paragraphs to handle very long messages
                let paragraphs = message.content.components(separatedBy: "\n\n")
                var messageY = currentY
                
                // Check if header fits on current page
                if messageY + headerSize.height > pageBottom {
                    // Draw page number at bottom center
                    let pageString = "Page \(pageNumber)"
                    let pageAttr = NSAttributedString(string: pageString, attributes: footerAttributes)
                    let pageTextSize = pageAttr.boundingRect(with: CGSize(width: contentWidth, height: 20), options: [], context: nil)
                    let centeredX = (pageSize.width - pageTextSize.width) / 2
                    pageAttr.draw(at: CGPoint(x: centeredX, y: pageSize.height - 30))
                    
                    context.beginPage()
                    messageY = margin
                    pageNumber += 1
                }
                
                // Draw header
                headerString.draw(in: CGRect(x: margin, y: messageY, width: contentWidth, height: headerSize.height))
                messageY += headerSize.height + 5
                
                // Draw content paragraphs
                for paragraph in paragraphs {
                    if !paragraph.isEmpty {
                        let contentString = NSAttributedString(string: paragraph, attributes: contentAttributes)
                        let contentSize = contentString.boundingRect(
                            with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            context: nil
                        )
                        
                        // Check if content fits on current page
                        if messageY + contentSize.height > pageBottom {
                            // Draw page number at bottom center
                            let pageString = "Page \(pageNumber)"
                            let pageAttr = NSAttributedString(string: pageString, attributes: footerAttributes)
                            let pageTextSize = pageAttr.boundingRect(with: CGSize(width: contentWidth, height: 20), options: [], context: nil)
                            let centeredX = (pageSize.width - pageTextSize.width) / 2
                            pageAttr.draw(at: CGPoint(x: centeredX, y: pageSize.height - 30))
                            
                            context.beginPage()
                            messageY = margin
                            pageNumber += 1
                        }
                        
                        // Draw content
                        contentString.draw(in: CGRect(x: margin, y: messageY, width: contentWidth, height: contentSize.height))
                        messageY += contentSize.height + 10
                    }
                }
                
                currentY = messageY + 10 // Extra spacing between messages
            }
            
            // Draw final page number at bottom center
            let pageString = "Page \(pageNumber)"
            let pageAttr = NSAttributedString(string: pageString, attributes: footerAttributes)
            let pageTextSize = pageAttr.boundingRect(with: CGSize(width: contentWidth, height: 20), options: [], context: nil)
            let centeredX = (pageSize.width - pageTextSize.width) / 2
            pageAttr.draw(at: CGPoint(x: centeredX, y: pageSize.height - 30))
        }
    }
}
