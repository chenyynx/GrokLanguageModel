//
//  TripPlannerView.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import FoundationModels
import SwiftUI

/// The Structured Output demo: Grok fills in a `@Generable` trip plan, and
/// the view renders each field as soon as it streams in.
struct TripPlannerView: View {
    private enum Presentation: String, CaseIterable {
        case plan = "Plan"
        case json = "JSON"
    }

    @Bindable var planner: TripPlannerModel
    @Environment(AppSettings.self) private var settings
    @State private var presentation = Presentation.plan
    @AppStorage("showsTripTranscript") private var showsTranscript = false

    var body: some View {
        HStack(spacing: 0) {
            form
                .frame(minWidth: 250, maxWidth: 330)
            Divider()
            Group {
                switch presentation {
                case .plan: planContent
                case .json: jsonContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .errorBanner($planner.error)
        .navigationTitle("Structured Output")
        .navigationSubtitle("@Generable TripPlan")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Presentation", selection: $presentation) {
                    ForEach(Presentation.allCases, id: \.self) { presentation in
                        Text(presentation.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .help("Show the plan, or the raw generated content")
            }
        }
        .transcriptInspector(for: planner.session, isResponding: planner.isGenerating, isPresented: $showsTranscript)
        .task {
            // Screenshot hook: `-demo structuredOutput -demoPrompt "…"` plans a
            // trip to that destination once at launch.
            if let destination = settings.consumeDemoPrompt() {
                planner.destination = destination
                planner.generate(using: settings.selectedModel)
            }
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section("Trip") {
                TextField("Destination", text: $planner.destination)
                Stepper(value: $planner.days, in: 1...7) {
                    LabeledContent("Days", value: planner.days.formatted())
                }
                TextField("Interests", text: $planner.interests, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section {
                if planner.isGenerating {
                    Button(role: .cancel) {
                        planner.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Stop generating (⌘.)")
                } else {
                    Button {
                        planner.generate(using: settings.selectedModel)
                    } label: {
                        Label("Generate Plan", systemImage: "wand.and.sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Generate a plan (⌘Return)")
                    .disabled(!planner.canGenerate)
                }
            } footer: {
                Text("Calls `streamResponse(to:generating:)` with `TripPlan.self`. Each snapshot is a `TripPlan.PartiallyGenerated` whose properties fill in as Grok writes them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Plan

    @ViewBuilder
    private var planContent: some View {
        if let plan = planner.plan {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header(for: plan)
                    if let budget = plan.budget {
                        BudgetSummary(budget: budget)
                    }
                    if let days = plan.days, !days.isEmpty {
                        section("Itinerary", systemImage: "calendar") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)], spacing: 14) {
                                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                    DayCard(number: index + 1, day: day)
                                }
                            }
                        }
                    }
                    if let packingList = plan.packingList, !packingList.isEmpty {
                        section("Packing List", systemImage: "suitcase.rolling") {
                            FlowLayout(spacing: 8) {
                                ForEach(Array(packingList.enumerated()), id: \.offset) { _, item in
                                    Text(item)
                                        .font(.callout)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.tint.opacity(0.12), in: .capsule)
                                }
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 980, alignment: .leading)
                .animation(.smooth, value: plan.days?.count)
                .animation(.smooth, value: plan.packingList?.count)
            }
        } else if planner.isGenerating {
            ProgressView("Planning your trip…")
        } else {
            ContentUnavailableView {
                Label("Plan a Trip", systemImage: "airplane.departure")
            } description: {
                Text("Describe a trip, and Grok fills in a `@Generable` `TripPlan` field by field.")
            }
        }
    }

    private func header(for plan: TripPlan.PartiallyGenerated) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.destination ?? " ")
                    .font(.largeTitle.bold())
                if let pace = plan.pace {
                    Text(pace.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.15), in: .capsule)
                        .foregroundStyle(.tint)
                }
            }
            if let tagline = plan.tagline {
                Text(tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
    }

    // MARK: JSON

    @ViewBuilder
    private var jsonContent: some View {
        if planner.json.isEmpty {
            ContentUnavailableView(
                "No Content Yet",
                systemImage: "curlybraces",
                description: Text("Generate a plan to see the raw `GeneratedContent` as it streams.")
            )
        } else {
            ScrollView([.vertical, .horizontal]) {
                Text(planner.json)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Components

/// Stat tiles for a partially generated budget.
private struct BudgetSummary: View {
    let budget: Budget.PartiallyGenerated

    var body: some View {
        // Four tiles in a row, or two rows of two when the window is narrow.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                costTiles
                totalTile
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tile("Lodging", budget.lodging, systemImage: "bed.double")
                    tile("Food", budget.food, systemImage: "fork.knife")
                }
                GridRow {
                    tile("Activities", budget.activities, systemImage: "ticket")
                    totalTile
                }
            }
        }
    }

    @ViewBuilder
    private var costTiles: some View {
        tile("Lodging", budget.lodging, systemImage: "bed.double")
        tile("Food", budget.food, systemImage: "fork.knife")
        tile("Activities", budget.activities, systemImage: "ticket")
    }

    private var totalTile: some View {
        tile("Total", total, systemImage: "dollarsign.circle", isProminent: true)
    }

    private var total: Int? {
        guard let lodging = budget.lodging, let food = budget.food, let activities = budget.activities else { return nil }
        return lodging + food + activities
    }

    private func tile(_ title: String, _ amount: Int?, systemImage: String, isProminent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(isProminent ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            Text(amount.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(0))) } ?? "—")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(amount ?? 0)))
                .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(isProminent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.5)), in: .rect(cornerRadius: 12))
        .animation(.smooth, value: amount)
    }
}

/// A card for one day of the itinerary.
private struct DayCard: View {
    let number: Int
    let day: DayPlan.PartiallyGenerated

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Day \(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(day.title ?? "…")
                .font(.headline)
            if let activities = day.activities {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(activities.enumerated()), id: \.offset) { _, activity in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(activity)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}

extension Pace {
    var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .balanced: "Balanced"
        case .packed: "Packed"
        }
    }
}

/// A layout that places its subviews in rows, wrapping to a new row when
/// one fills up.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
