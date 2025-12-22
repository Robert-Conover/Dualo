//
//  View+Extensions.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct KeyboardResponsive: ViewModifier {
    @State private var keyboardBottomInset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardBottomInset)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardInset(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardInset(from: notification)
            }
    }
    
    private func updateKeyboardInset(from notification: Notification) {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
            let window = windowScene.windows.first(where: { $0.isKeyWindow }),
            let endFrameScreen = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }
        
        // Convert the keyboard frame into the window’s coordinate space.
        let endFrame = window.convert(endFrameScreen, from: nil)
        let windowHeight = window.bounds.height
        
        // Only treat the keyboard as “covering the bottom” if it actually reaches the bottom edge
        // (handles floating keyboards on iPad).
        let touchesBottom = endFrame.maxY >= windowHeight - 1
        let overlap = touchesBottom ? max(0, windowHeight - endFrame.minY) : 0
        
        // Subtract the existing bottom safe area (home indicator) so we don’t overshoot.
        let safeBottom = window.safeAreaInsets.bottom
        let targetInset = max(0, overlap - safeBottom)
        
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            keyboardBottomInset = targetInset
        }
    }
}

extension View {
    func keyboardResponsive() -> some View {
        modifier(KeyboardResponsive())
    }
}