//
//  WeatherTool.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels

/// A tool that reports simulated weather conditions for a city.
///
/// Sessions call tools off the main actor, so the tool is `nonisolated`
/// and its `call(arguments:)` method is `@concurrent`.
nonisolated struct WeatherTool: Tool {
    let name = "getWeather"
    let description = "Gets the current weather conditions for a city."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The city, like \"Paris\" or \"Tokyo, Japan\"")
        var city: String

        @Guide(description: "The unit to report temperatures in")
        var unit: TemperatureUnit
    }

    @Generable
    nonisolated enum TemperatureUnit {
        case celsius
        case fahrenheit
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        // Pretend to make a network request, so the tool log shows the call in flight.
        try await Task.sleep(for: .milliseconds(700))

        let report = WeatherReport(city: arguments.city)
        let temperature = switch arguments.unit {
        case .celsius: "\(report.celsius)°C"
        case .fahrenheit: "\(Int((Double(report.celsius) * 9 / 5 + 32).rounded()))°F"
        }
        return "\(arguments.city): \(temperature), \(report.condition), \(report.humidity)% humidity, "
            + "wind \(report.windSpeed) km/h. (Simulated data.)"
    }
}

/// Simulated weather that stays the same for each city name.
nonisolated struct WeatherReport {
    private static let conditions = [
        "clear skies", "sunny", "partly cloudy", "overcast", "light rain",
        "heavy showers", "thunderstorms", "fog", "light snow", "windy",
    ]

    var celsius: Int
    var condition: String
    var humidity: Int
    var windSpeed: Int

    init(city: String) {
        var generator = SeededRandomNumberGenerator(seed: city.lowercased().trimmingCharacters(in: .whitespaces))
        celsius = Int.random(in: -8...34, using: &generator)
        condition = Self.conditions.randomElement(using: &generator) ?? "clear skies"
        humidity = Int.random(in: 25...95, using: &generator)
        windSpeed = Int.random(in: 0...45, using: &generator)
    }
}

/// A random number generator that produces the same sequence for the same seed.
nonisolated struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        // FNV-1a, because `Hasher` is seeded differently on every launch.
        state = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            state ^= UInt64(byte)
            state &*= 0x0000_0100_0000_01B3
        }
    }

    mutating func next() -> UInt64 {
        // SplitMix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
