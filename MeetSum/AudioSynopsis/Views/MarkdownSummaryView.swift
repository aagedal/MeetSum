//
//  MarkdownSummaryView.swift
//  Audio Synopsis
//
//  Renders markdown-formatted summary with thinking tag support
//

import SwiftUI

struct MarkdownSummaryView: View {
    let rawSummary: String
    var searchText: String = ""
    var currentMatchIndex: Int = 0

    private var parsed: ParsedOutput {
        ThinkingTagParser.parse(rawSummary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(contentLines.enumerated()), id: \.offset) { index, line in
                            renderLine(line)
                                .padding(4)
                                .background(highlightColor(for: line, lineIndex: index))
                                .cornerRadius(4)
                                .id(index)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .onChange(of: currentMatchIndex) {
                    let indices = matchingLineIndices
                    if currentMatchIndex < indices.count {
                        withAnimation {
                            proxy.scrollTo(indices[currentMatchIndex], anchor: .center)
                        }
                    }
                }
                .onChange(of: searchText) {
                    let indices = matchingLineIndices
                    if !indices.isEmpty {
                        withAnimation {
                            proxy.scrollTo(indices[0], anchor: .center)
                        }
                    }
                }
            }

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

    private var matchingLineIndices: [Int] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return contentLines.enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.lowercased().contains(query) ? index : nil
        }
    }

    private func highlightColor(for line: String, lineIndex: Int) -> Color {
        guard !searchText.isEmpty else { return .clear }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased().contains(searchText.lowercased()) else { return .clear }

        let indices = matchingLineIndices
        if let matchPos = indices.firstIndex(of: lineIndex), matchPos == currentMatchIndex {
            return Color.yellow.opacity(0.3)
        }
        return Color.yellow.opacity(0.1)
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
