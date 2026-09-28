//
//  CalculatorTool.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels

/// A tool that evaluates arithmetic expressions exactly.
///
/// Language models are better at deciding what to compute than at computing
/// it, so the tool does the math.
nonisolated struct CalculatorTool: Tool {
    let name = "calculate"
    let description = """
        Evaluates an arithmetic expression exactly. Use it for any math instead of calculating in your head. \
        Supports + - * / % ^, parentheses, pi, e, and the functions sqrt, abs, round, floor, ceil, \
        sin, cos, tan, log, log2, ln, and exp.
        """

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The expression to evaluate, like \"(75 - 32) * 5 / 9\"")
        var expression: String
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        do {
            let value = try ExpressionEvaluator.evaluate(arguments.expression)
            return "\(arguments.expression) = \(ExpressionEvaluator.format(value))"
        } catch {
            // Tell the model what went wrong, so it can fix the expression and try again.
            return "Error: \(error.localizedDescription)"
        }
    }
}
