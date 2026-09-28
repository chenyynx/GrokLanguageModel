//
//  VisionView.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// The Vision demo: drop or choose an image, then ask Grok about it.
struct VisionView: View {
    @Bindable var model: VisionModel
    @Environment(AppSettings.self) private var settings
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @AppStorage("showsVisionTranscript") private var showsTranscript = false

    var body: some View {
        // The image sits next to the question, or above it when the window is narrow.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                imageWell
                    .frame(minWidth: 200, idealWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                questionAndAnswer
                    .frame(minWidth: 260, idealWidth: 260, maxWidth: 380)
            }
            VStack(spacing: 16) {
                imageWell
                    .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
                questionAndAnswer
            }
        }
        .padding(20)
        .errorBanner($model.error)
        .navigationTitle("Vision")
        .navigationSubtitle(model.imageName ?? "Image attachments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Choose Image…", systemImage: "photo.badge.plus") {
                    isImporting = true
                }
                .help("Choose an image to ask about")
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                model.loadImage(from: url)
            case .failure(let error):
                model.error = PresentableError(error)
            }
        }
        .transcriptInspector(for: model.session, isResponding: model.isResponding, isPresented: $showsTranscript)
    }

    private var questionAndAnswer: some View {
        VStack(alignment: .leading, spacing: 20) {
            questionSection
            answerSection
        }
    }

    // MARK: Image

    private var imageWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary.opacity(0.35))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 1.5, dash: model.image == nil ? [7, 5] : [])
                )

            if let image = model.image {
                Image(image, scale: 1, label: Text(model.imageName ?? "Image"))
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 10))
                    .shadow(radius: 8, y: 4)
                    .padding(20)
            } else {
                ContentUnavailableView {
                    Label("Drop an Image", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Drag an image here, or choose one from your Mac.")
                } actions: {
                    Button("Choose Image…") { isImporting = true }
                    Button("Use Sample Image") { model.useSampleImage() }
                }
            }
        }
        .animation(.snappy, value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first {
                model.loadImage(from: url)
            }
        }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active: isDropTargeted = true
            default: isDropTargeted = false
            }
        }
    }

    // MARK: Question

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Question")
                    .font(.headline)
                Spacer()
                Menu("Examples") {
                    ForEach(VisionModel.sampleQuestions, id: \.self) { question in
                        Button(question) { model.question = question }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            TextField("Ask about the image", text: $model.question, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.ask(using: settings.selectedModel) }
            HStack {
                if model.image != nil {
                    Button("Sample Image", systemImage: "wand.and.stars") {
                        model.useSampleImage()
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                if model.isResponding {
                    Button("Stop", systemImage: "stop.fill", role: .cancel) {
                        model.stop()
                    }
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Stop (⌘.)")
                } else {
                    Button("Ask Grok", systemImage: "eye") {
                        model.ask(using: settings.selectedModel)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Ask about the image (⌘Return)")
                    .disabled(!model.canAsk)
                }
            }
            Text("Sends `session.respond { question; Attachment(image) }`.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Answer

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Answer")
                .font(.headline)
            ScrollView {
                Group {
                    if !model.answer.isEmpty {
                        MarkdownText(model.answer)
                    } else if model.isResponding {
                        Label {
                            Text("Looking at the image…")
                        } icon: {
                            Image(systemName: "eye")
                                .symbolEffect(.pulse, options: .repeat(.continuous))
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text(model.image == nil ? "Add an image to get started." : "Ask a question to see Grok's answer.")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(maxHeight: .infinity)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
            if let usage = model.usage {
                UsageLabel(usage: usage)
            }
        }
    }
}
