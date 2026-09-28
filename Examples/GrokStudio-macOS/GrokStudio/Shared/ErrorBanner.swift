//
//  ErrorBanner.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import SwiftUI

/// An inline banner that describes an error, with a shortcut to Settings
/// when changing a setting could fix it.
struct ErrorBanner: View {
    let error: PresentableError
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(error.title)
                    .font(.headline)
                Text(error.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let suggestion = error.suggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if error.opensSettings {
                SettingsLink {
                    Text("Open Settings…")
                }
            }
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.orange.opacity(0.35))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Shows an error banner below the view while there's an error.
    func errorBanner(_ error: Binding<PresentableError?>) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if let presented = error.wrappedValue {
                ErrorBanner(error: presented) {
                    error.wrappedValue = nil
                }
                .padding([.horizontal, .bottom])
            }
        }
        .animation(.snappy, value: error.wrappedValue?.id)
    }
}
