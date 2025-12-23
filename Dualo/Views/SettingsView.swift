//
//  SettingsView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject private var viewModel: ChatViewModel
    @ObservedObject private var localModelManager = LocalModelManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // Mode toggle state - defaults to On-Device (.local)
    // This persists throughout the Settings session until dismissed
    @State private var selectedMode: SettingsMode = .local
    
    // App version from bundle
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    init(viewModel: ChatViewModel? = nil) {
        self.viewModel = viewModel ?? ChatViewModel()
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Mode Toggle Section
                Section {
                    SettingsModeToggle(selectedMode: $selectedMode)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                
                // App Section
                Section("App") {
                    NavigationLink {
                        if selectedMode == .local {
                            LocalModelsView()
                        } else {
                            CloudAPISettingsView(viewModel: viewModel)
                        }
                    } label: {
                        SettingsRowGradient(
                            icon: selectedMode == .local ? "iphone" : "cloud.fill",
                            title: "Manage models",
                            gradientColors: selectedMode == .local ? [.green, .mint] : [.blue, .purple],
                            subtitle: selectedMode == .local ? "On-device models" : "Cloud API providers"
                        )
                    }
                }
                
                // About Section
                Section("About") {
                    SettingsInfoRow(
                        icon: "info.circle",
                        title: "Version",
                        value: appVersion,
                        color: .gray
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
