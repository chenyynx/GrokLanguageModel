//
//  TripPlan.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import FoundationModels

// Grok models turn `@Generable` types into a strict JSON schema, so every
// response decodes. The types are `nonisolated` because the app isolates
// declarations to the main actor by default, and generation happens off it.

/// A travel itinerary that Grok generates as structured output.
@Generable(description: "A travel itinerary")
nonisolated struct TripPlan {
    @Guide(description: "The destination, like \"Kyoto, Japan\"")
    var destination: String

    @Guide(description: "A one-sentence pitch for the trip")
    var tagline: String

    @Guide(description: "How full the days are")
    var pace: Pace

    @Guide(description: "A plan for each day of the trip, in order", .count(1...7))
    var days: [DayPlan]

    @Guide(description: "Things to pack for the destination, season, and activities", .count(4...10))
    var packingList: [String]

    @Guide(description: "The estimated cost of the trip per person")
    var budget: Budget
}

/// How full a trip's days are.
@Generable
nonisolated enum Pace {
    case relaxed
    case balanced
    case packed
}

/// The plan for one day of a trip.
@Generable
nonisolated struct DayPlan {
    @Guide(description: "A short, evocative title for the day")
    var title: String

    @Guide(description: "Specific things to do, in order, naming real places", .count(2...4))
    var activities: [String]
}

/// The estimated cost of a trip per person, in US dollars.
@Generable
nonisolated struct Budget {
    @Guide(description: "Lodging for the whole trip, in US dollars", .range(50...20_000))
    var lodging: Int

    @Guide(description: "Food and drink for the whole trip, in US dollars", .range(20...10_000))
    var food: Int

    @Guide(description: "Activities, tickets, and local transport for the whole trip, in US dollars", .range(0...10_000))
    var activities: Int
}
