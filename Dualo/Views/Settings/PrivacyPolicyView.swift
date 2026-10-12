//
//  PrivacyPolicyView.swift
//  Dualo
//
//  The privacy policy, readable offline from Settings. Apple asks for it to be
//  easy to find in the app as well as on the App Store.
//

import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Effective \(PrivacyPolicy.effectiveDate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(PrivacyPolicy.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.paragraphs, id: \.self) { paragraph in
                            Text(LocalizedStringKey(paragraph))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: PrivacyPolicy.webURL)
            }
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
