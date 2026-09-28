//
//  MarkdownText.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import AppKit
import SwiftUI

/// Renders the Markdown that Grok writes: headings, lists, quotes, code
/// blocks, and tables, with inline styles and links.
///
/// The renderer is forgiving so that it can draw partial Markdown while a
/// response streams in, like a code block that isn't closed yet.
struct MarkdownText: View {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.blocks(in: markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case .listItem(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(Self.inline(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .quote(let text):
            Text(Self.inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tint.opacity(0.6))
                        .frame(width: 3)
                }
        case .code(let language, let code):
            CodeBlock(language: language, code: code)
        case .table(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.callout.monospaced())
                    .padding(10)
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        case .rule:
            Divider()
        }
    }

    /// Parses inline Markdown, like `**bold**`, `` `code` ``, and links.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// A fenced code block with a language label and a copy button.
private struct CodeBlock: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollView(.horizontal) {
                Text(code)
                    .font(.callout.monospaced())
                    .padding(10)
            }
        }
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

/// A block-level element of a Markdown document.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case listItem(marker: String, text: String, depth: Int)
    case quote(String)
    case code(language: String?, code: String)
    case table(String)
    case rule

    /// Splits Markdown into blocks.
    static func blocks(in markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String]?
        var codeLanguage: String?
        var tableLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }

        func flushTable() {
            if !tableLines.isEmpty {
                blocks.append(.table(tableLines.joined(separator: "\n")))
                tableLines.removeAll()
            }
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code blocks keep their lines verbatim until the closing fence.
            if var lines = codeLines {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, code: lines.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    lines.append(line)
                    codeLines = lines
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushTable()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                codeLanguage = language.isEmpty ? nil : language
                codeLines = []
                continue
            }

            if trimmed.hasPrefix("|") {
                flushParagraph()
                tableLines.append(trimmed)
                continue
            }
            flushTable()

            if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(heading)
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
            } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if let item = listItem(in: line) {
                flushParagraph()
                blocks.append(item)
            } else {
                paragraph.append(trimmed)
            }
        }

        flushParagraph()
        flushTable()
        if let codeLines {
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        return blocks
    }

    private static func heading(in line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(in line: String) -> MarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let content = line.dropFirst(indent)
        let depth = min(indent / 2, 4)

        for bullet in ["- ", "* ", "+ "] where content.hasPrefix(bullet) {
            return .listItem(marker: "•", text: String(content.dropFirst(2)), depth: depth)
        }

        let digits = content.prefix(while: \.isNumber)
        let rest = content.dropFirst(digits.count)
        if !digits.isEmpty, digits.count <= 3, rest.hasPrefix(". ") || rest.hasPrefix(") ") {
            return .listItem(marker: "\(digits).", text: String(rest.dropFirst(2)), depth: depth)
        }
        return nil
    }
}
