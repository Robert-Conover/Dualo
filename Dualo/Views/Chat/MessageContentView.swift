//
//  MessageContentView.swift
//  Dualo
//
//  Created by Robert Conover on 8/13/25.
//

import SwiftUI

struct MessageContentView: View {
    let content: String
    let isUser: Bool
    @State private var showCopyToast = false
    @State private var copiedMessage = ""
    @State private var parsedContent: [MessageContentRenderer.ContentType]

    init(content: String, isUser: Bool) {
        self.content = content
        self.isUser = isUser
        // Parse up front: starting empty and filling in later renders one frame with
        // no height, which snaps the chat's scroll position to the top when a reply finishes.
        _parsedContent = State(initialValue: MessageContentRenderer.parse(content))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(parsedContent) { section in
                switch section {
                case .text(let attributedString, _):
                    Text(attributedString)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(isUser ? .white : .primary)
                        .textSelection(.enabled)
                        .tint(isUser ? .white : .blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.openURL, OpenURLAction { url in
                            UIApplication.shared.open(url)
                            return .handled
                        })
                    
                case .codeBlock(let code, let language, _):
                    CodeBlockView(code: code, language: language)
                        .overlay(alignment: .bottom) {
                            if showCopyToast && copiedMessage == code {
                                ToastView(
                                    message: "Code copied!",
                                    icon: "doc.on.doc.fill",
                                    isShowing: $showCopyToast
                                )
                                .offset(y: 50)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                ))
                            }
                        }
                    
                case .thinkingBlock(let thinkingContent, _):
                    ThinkingBlockView(content: thinkingContent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: content) { _, newContent in
            parsedContent = MessageContentRenderer.parse(newContent)
        }
    }
}

struct MessageContentView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            MessageContentView(
                content: """
                Here's a **Swift** function that calculates the *factorial*:
                
                ```swift
                func factorial(_ n: Int) -> Int {
                    guard n > 0 else { return 1 }
                    return n * factorial(n - 1)
                }
                ```
                
                This uses `recursion` to calculate the result. You can also use a loop approach:
                
                ```swift
                func factorialIterative(_ n: Int) -> Int {
                    var result = 1
                    for i in 1...max(n, 1) {
                        result *= i
                    }
                    return result
                }
                ```
                
                Visit [Apple Developer](https://developer.apple.com) for more info.
                """,
                isUser: false
            )
            .padding()
            .background(Color.gray.opacity(0.1))
        }
    }
}