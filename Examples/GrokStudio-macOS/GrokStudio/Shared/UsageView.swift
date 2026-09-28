//
//  UsageView.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import FoundationModels
import SwiftUI

/// A table of the tokens that a response or a session used.
///
/// Grok models report input, cached input, output, and reasoning tokens,
/// which Foundation Models exposes as `LanguageModelSession.Usage`.
struct UsageGrid: View {
    let usage: LanguageModelSession.Usage

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            row("Input", usage.input.totalTokenCount, systemImage: "arrow.down.circle")
            row("Cached input", usage.input.cachedTokenCount, systemImage: "memorychip")
            row("Output", usage.output.totalTokenCount, systemImage: "arrow.up.circle")
            row("Reasoning", usage.output.reasoningTokenCount, systemImage: "brain")
            Divider()
            row("Total", usage.totalTokenCount, systemImage: "sum", isEmphasized: true)
        }
        .font(.callout)
    }

    private func row(_ title: String, _ count: Int, systemImage: String, isEmphasized: Bool = false) -> some View {
        GridRow {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isEmphasized ? .primary : .secondary)
            Text(count, format: .number)
                .fontWeight(isEmphasized ? .semibold : .regular)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
                .gridColumnAlignment(.trailing)
        }
    }
}

/// A one-line summary of token usage, like "1,204 in · 318 out · 256 reasoning".
struct UsageLabel: View {
    let usage: LanguageModelSession.Usage

    var body: some View {
        Label {
            Text("\(usage.input.totalTokenCount.formatted()) in · \(usage.output.totalTokenCount.formatted()) out · \(usage.output.reasoningTokenCount.formatted()) reasoning")
                .monospacedDigit()
        } icon: {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
