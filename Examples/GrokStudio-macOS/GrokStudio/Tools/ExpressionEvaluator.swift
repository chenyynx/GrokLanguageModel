//
//  ExpressionEvaluator.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation

/// Evaluates arithmetic expressions like `(72 - 18) * 5 / 9` or `sqrt(2) ^ 3`.
///
/// It supports `+`, `-`, `*`, `/`, `%`, `^` (right-associative), parentheses,
/// the constants `pi` and `e`, and the functions `sqrt`, `abs`, `round`,
/// `floor`, `ceil`, `sin`, `cos`, `tan`, `log` (base 10), `log2`, `ln`, and `exp`.
nonisolated enum ExpressionEvaluator {
    enum EvaluationError: LocalizedError, Equatable {
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case unknownName(String)
        case invalidNumber(String)
        case tooDeeplyNested

        var errorDescription: String? {
            switch self {
            case .unexpectedCharacter(let character): "Unexpected character \"\(character)\"."
            case .unexpectedEnd: "The expression ended unexpectedly."
            case .unknownName(let name): "Unknown function or constant \"\(name)\"."
            case .invalidNumber(let text): "\"\(text)\" isn't a valid number."
            case .tooDeeplyNested: "The expression is nested too deeply."
            }
        }
    }

    /// Evaluates an expression, or throws an error that describes why it can't.
    static func evaluate(_ expression: String) throws -> Double {
        var parser = Parser(expression)
        let value = try parser.parseSum()
        parser.skipWhitespace()
        if let character = parser.peek() {
            throw EvaluationError.unexpectedCharacter(character)
        }
        return value
    }

    /// Formats a result without a trailing ".0" or floating-point noise.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "undefined" : (value > 0 ? "infinity" : "-infinity") }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(format: "%.12g", value)
    }

    /// A recursive-descent parser. Each method parses one precedence level:
    ///
    ///     sum     := product (("+" | "-") product)*
    ///     product := unary (("*" | "/" | "%") unary)*
    ///     unary   := ("-" | "+") unary | power
    ///     power   := primary ("^" unary)?
    ///     primary := number | name | name "(" sum ")" | "(" sum ")"
    private struct Parser {
        /// How deeply parentheses, signs, exponents, and function calls can
        /// nest. Each level recurses, and the model writes the expression, so
        /// the limit keeps a pathological one from overflowing the stack of the
        /// thread that calls the tool, which would crash the app.
        private static let maximumDepth = 100

        private let characters: [Character]
        private var index = 0
        private var depth = 0

        init(_ text: String) {
            // Accept the typographic operators that a model might write.
            let normalized = text
                .replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: "**", with: "^")
            characters = Array(normalized)
        }

        func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        mutating func skipWhitespace() {
            while let character = peek(), character.isWhitespace {
                index += 1
            }
        }

        private mutating func consume(_ character: Character) -> Bool {
            skipWhitespace()
            guard peek() == character else { return false }
            index += 1
            return true
        }

        mutating func parseSum() throws -> Double {
            var value = try parseProduct()
            while true {
                if consume("+") {
                    value += try parseProduct()
                } else if consume("-") {
                    value -= try parseProduct()
                } else {
                    return value
                }
            }
        }

        private mutating func parseProduct() throws -> Double {
            var value = try parseUnary()
            while true {
                if consume("*") {
                    value *= try parseUnary()
                } else if consume("/") {
                    value /= try parseUnary()
                } else if consume("%") {
                    value = value.truncatingRemainder(dividingBy: try parseUnary())
                } else {
                    return value
                }
            }
        }

        private mutating func parseUnary() throws -> Double {
            // Every recursive path goes through this method, so this limits
            // the nesting of the whole expression.
            depth += 1
            defer { depth -= 1 }
            guard depth <= Self.maximumDepth else { throw EvaluationError.tooDeeplyNested }

            if consume("-") {
                return -(try parseUnary())
            }
            if consume("+") {
                return try parseUnary()
            }
            return try parsePower()
        }

        private mutating func parsePower() throws -> Double {
            let base = try parsePrimary()
            if consume("^") {
                return pow(base, try parseUnary())
            }
            return base
        }

        private mutating func parsePrimary() throws -> Double {
            skipWhitespace()
            guard let character = peek() else { throw EvaluationError.unexpectedEnd }

            if consume("(") {
                let value = try parseSum()
                guard consume(")") else { throw peek().map(EvaluationError.unexpectedCharacter) ?? .unexpectedEnd }
                return value
            }
            if character.isNumber || character == "." {
                return try parseNumber()
            }
            if character.isLetter {
                return try parseName()
            }
            throw EvaluationError.unexpectedCharacter(character)
        }

        private mutating func parseNumber() throws -> Double {
            let start = index
            while let character = peek(), character.isNumber || character == "." || character == "_" {
                index += 1
            }
            // An exponent, like the "e-3" in "2.5e-3".
            if peek() == "e" || peek() == "E" {
                let mark = index
                index += 1
                if peek() == "+" || peek() == "-" {
                    index += 1
                }
                if let character = peek(), character.isNumber {
                    while let character = peek(), character.isNumber {
                        index += 1
                    }
                } else {
                    index = mark
                }
            }
            let text = String(characters[start..<index]).replacingOccurrences(of: "_", with: "")
            guard let value = Double(text) else { throw EvaluationError.invalidNumber(text) }
            return value
        }

        private mutating func parseName() throws -> Double {
            let start = index
            while let character = peek(), character.isLetter || character.isNumber {
                index += 1
            }
            let name = String(characters[start..<index]).lowercased()

            if consume("(") {
                let argument = try parseSum()
                guard consume(")") else { throw peek().map(EvaluationError.unexpectedCharacter) ?? .unexpectedEnd }
                switch name {
                case "sqrt": return argument.squareRoot()
                case "abs": return abs(argument)
                case "round": return argument.rounded()
                case "floor": return argument.rounded(.down)
                case "ceil": return argument.rounded(.up)
                case "sin": return sin(argument)
                case "cos": return cos(argument)
                case "tan": return tan(argument)
                case "log": return log10(argument)
                case "log2": return log2(argument)
                case "ln": return log(argument)
                case "exp": return exp(argument)
                default: throw EvaluationError.unknownName(name)
                }
            }

            switch name {
            case "pi", "π": return .pi
            case "e": return M_E
            default: throw EvaluationError.unknownName(name)
            }
        }
    }
}
