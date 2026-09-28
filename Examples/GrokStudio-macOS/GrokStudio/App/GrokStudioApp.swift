//
//  GrokStudioApp.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import SwiftUI

/// GrokStudio shows off the GrokLanguageModel package: every demo in the
/// sidebar uses the Foundation Models API with a Grok model.
@main
struct GrokStudioApp: App {
    /// Creating the settings applies the saved API key to
    /// `GrokConfiguration.default` before any session exists.
    @State private var settings = AppSettings()

    var body: some Scene {
        Window("GrokStudio", id: "main") {
            ContentView()
                .environment(settings)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            // View > Show Inspector (⌃⌘I) toggles each demo's transcript inspector.
            InspectorCommands()
        }

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
