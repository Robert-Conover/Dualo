//
//  ModelMemoryDivider.swift
//  Dualo
//
//  Marks where a local model's memory of a long chat starts.
//

import SwiftUI

struct ModelMemoryDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            line
            Text("The model no longer remembers messages above")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .layoutPriority(1)
            line
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("modelMemoryDivider")
    }

    private var line: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 1)
            .frame(minWidth: 16)
    }
}

#Preview {
    ModelMemoryDivider()
}
