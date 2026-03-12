//
//  MarkdownSummaryView.swift
//  MeetSum
//
//  Renders markdown-formatted summary with thinking tag support
//

import SwiftUI

struct MarkdownSummaryView: View {
    let rawSummary: String

    private var parsed: ParsedOutput {
        ThinkingTagParser.parse(rawSummary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(contentLines.enumerated()), id: \.offset) { _, line in
                        renderLine(line)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            if let thinking = parsed.thinkingContent {
                DisclosureGroup("Model Thinking") {
                    ScrollView {
                        Text(thinking)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
                }
                .padding(.top, 8)
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private var contentLines: [String] {
        parsed.visibleContent.components(separatedBy: "\n")
    }

    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("### ") {
            Text(String(trimmed.dropFirst(4)))
                .font(.headline)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("## ") {
            Text(String(trimmed.dropFirst(3)))
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 6)
        } else if trimmed.hasPrefix("# ") {
            Text(String(trimmed.dropFirst(2)))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 8)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .padding(.top, 4)
                inlineMarkdownText(String(trimmed.dropFirst(2)))
            }
            .padding(.leading, 12)
        } else if trimmed.isEmpty {
            Spacer().frame(height: 4)
        } else {
            inlineMarkdownText(trimmed)
        }
    }

    private func inlineMarkdownText(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        } else {
            return Text(text)
        }
    }
}
