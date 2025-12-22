//
//  HapticFeedback.swift
//  Dualo
//
//  Centralized haptic feedback utilities to avoid duplicate code.
//

import UIKit

/// Centralized haptic feedback utilities
enum HapticFeedback {
    /// Light impact feedback - used for button taps, selections
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium impact feedback - used for confirmations
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Heavy impact feedback - used for significant actions
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Soft impact feedback - subtle feedback
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Rigid impact feedback - more pronounced
    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// Success notification - used for completed actions
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification - used for cautionary feedback
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Error notification - used for failed actions
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Selection changed feedback - used for picker/selection changes
    static func selectionChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
