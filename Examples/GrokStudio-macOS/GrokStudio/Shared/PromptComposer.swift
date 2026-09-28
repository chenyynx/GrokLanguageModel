//
//  PromptComposer.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import SwiftUI

/// A text field for writing a prompt, with a button that sends it or stops
/// the response that's in progress.
struct PromptComposer: View {
    @Binding var text: String
    var placeholder: String
    var isResponding: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($isFocused)
                .onSubmit(send)
                .padding(.vertical, 11)
                .padding(.leading, 16)

            Group {
                if isResponding {
                    Button("Stop", systemImage: "stop.circle.fill", action: onStop)
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Stop responding (⌘.)")
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                        .disabled(!canSend)
                        .help("Send (Return)")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 26))
            .foregroundStyle(.tint)
            .padding(6)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend, !isResponding else { return }
        onSend()
    }
}
