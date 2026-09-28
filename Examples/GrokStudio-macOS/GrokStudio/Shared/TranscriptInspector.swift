//
//  TranscriptInspector.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import FoundationModels
import SwiftUI

/// An inspector that shows a session's live transcript and its cumulative
/// token usage.
///
/// `LanguageModelSession` is observable, so the inspector updates as entries
/// stream in: reasoning, tool calls, tool output, and the response.
struct TranscriptInspector: View {
    let session: LanguageModelSession?

    /// A Boolean value that indicates whether the session is responding.
    ///
    /// The session updates its transcript and usage off the main actor, so
    /// the inspector also redraws when the demo's response ends. That way it
    /// always shows the final entries and token counts.
    let isResponding: Bool

    var body: some View {
        if let session {
            List {
                Section("Session Usage") {
                    UsageGrid(usage: session.usage)
                        .padding(.vertical, 4)
                }
                Section {
                    ForEach(session.transcript) { entry in
                        TranscriptEntryRow(entry: entry)
                    }
                } header: {
                    HStack {
                        Text("Transcript")
                        if isResponding {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityLabel("Responding")
                        }
                        Spacer()
                        Text("^[\(session.transcript.count) entry](inflect: true)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
            .animation(.snappy, value: session.transcript.count)
        } else {
            ContentUnavailableView(
                "No Transcript Yet",
                systemImage: "list.bullet.rectangle",
                description: Text("Send a prompt to see the session's transcript entries and token usage.")
            )
        }
    }
}

/// A row that summarizes a transcript entry and expands to show all of it.
private struct TranscriptEntryRow: View {
    let entry: Transcript.Entry
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.displayText.isEmpty ? "—" : entry.displayText)
                    .font(entry.prefersMonospacedText ? .caption.monospaced() : .callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(entry.details) { detail in
                    LabeledContent(detail.label) {
                        Text(detail.value)
                            .monospaced()
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: entry.systemImage)
                    .foregroundStyle(entry.tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.kindTitle)
                        .font(.callout.weight(.semibold))
                    Text(entry.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

extension View {
    /// Adds a transcript inspector for a session, and a toolbar button that
    /// shows and hides it.
    func transcriptInspector(
        for session: LanguageModelSession?,
        isResponding: Bool,
        isPresented: Binding<Bool>
    ) -> some View {
        // Let the demo shrink below its natural size, and clip it if it has
        // to. When the demo's minimum width doesn't leave room for the
        // inspector, the split view can't settle, and AppKit throws an
        // exception while it updates constraints.
        frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .inspector(isPresented: isPresented) {
                TranscriptInspector(session: session, isResponding: isResponding)
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 440)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresented.wrappedValue.toggle()
                    } label: {
                        Label("Transcript", systemImage: "sidebar.trailing")
                    }
                    .help(isPresented.wrappedValue ? "Hide the transcript (⌃⌘I)" : "Show the transcript (⌃⌘I)")
                }
            }
    }
}
