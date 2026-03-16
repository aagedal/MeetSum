//
//  ChatBubbleView.swift
//  Audio Synopsis
//
//  Renders a single chat message bubble (user or assistant)
//

import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                bubbleContent

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.role == .assistant {
            assistantBubble
        } else {
            userBubble
        }
    }

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 4) {
            if isHovering {
                copyButton
            }

            Text(message.content)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(12)
        }
    }

    private var assistantBubble: some View {
        let parsed = ThinkingTagParser.parse(message.content)

        return VStack(alignment: .leading, spacing: 4) {
            // Thinking disclosure (if present)
            if let thinking = parsed.thinkingContent {
                DisclosureGroup("Thinking") {
                    ScrollView {
                        Text(thinking)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(maxHeight: 150)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Visible content with markdown rendering
            HStack(alignment: .top, spacing: 4) {
                markdownContent(parsed.visibleContent)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                if isHovering {
                    copyButton
                }
            }
        }
    }

    private var copyButton: some View {
        Button(action: {
            let cleaned = ThinkingTagParser.parse(message.content).visibleContent
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cleaned, forType: .string)
        }) {
            Image(systemName: "doc.on.doc")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy message")
    }

    @ViewBuilder
    private func markdownContent(_ text: String) -> some View {
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                renderLine(line)
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("### ") {
            Text(String(trimmed.dropFirst(4)))
                .font(.headline)
                .padding(.top, 2)
        } else if trimmed.hasPrefix("## ") {
            Text(String(trimmed.dropFirst(3)))
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("# ") {
            Text(String(trimmed.dropFirst(2)))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .padding(.top, 4)
                inlineMarkdown(String(trimmed.dropFirst(2)))
            }
            .padding(.leading, 8)
        } else if trimmed.isEmpty {
            Spacer().frame(height: 2)
        } else {
            inlineMarkdown(trimmed)
        }
    }

    private func inlineMarkdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        }
        return Text(text)
    }
}
