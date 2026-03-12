//
//  ThinkingTagParser.swift
//  MeetSum
//
//  Parses <think> tags from LLM output (e.g., Qwen3)
//

import Foundation

struct ParsedOutput {
    let thinkingContent: String?
    let visibleContent: String
}

struct ThinkingTagParser {
    private static let thinkingPattern = try! NSRegularExpression(
        pattern: "<think>([\\s\\S]*?)</think>",
        options: []
    )

    static func parse(_ rawOutput: String) -> ParsedOutput {
        let range = NSRange(rawOutput.startIndex..., in: rawOutput)
        let matches = thinkingPattern.matches(in: rawOutput, range: range)

        guard !matches.isEmpty else {
            return ParsedOutput(thinkingContent: nil, visibleContent: rawOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Extract thinking content
        var thinkingParts: [String] = []
        for match in matches {
            if let captureRange = Range(match.range(at: 1), in: rawOutput) {
                let content = String(rawOutput[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    thinkingParts.append(content)
                }
            }
        }

        // Remove thinking tags from visible content
        let visible = thinkingPattern.stringByReplacingMatches(
            in: rawOutput,
            range: range,
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedOutput(
            thinkingContent: thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n\n"),
            visibleContent: visible
        )
    }
}
