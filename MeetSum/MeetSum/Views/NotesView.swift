//
//  NotesView.swift
//  MeetSum
//
//  Timestamped notes panel using NSTextView
//

import SwiftUI
import AppKit

struct NotesView: View {
    @Binding var text: String
    var isRecording: Bool
    var currentTimestamp: () -> String
    var onTextChange: (() -> Void)?

    @State private var showingPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with preview toggle
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)

                Spacer()

                Button(action: { showingPreview.toggle() }) {
                    Image(systemName: showingPreview ? "pencil" : "eye")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(showingPreview ? "Edit notes" : "Preview markdown")
            }

            if showingPreview {
                // Markdown preview
                MarkdownNotesPreview(text: text)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
            } else {
                // NSTextView wrapper
                TimestampedTextView(
                    text: $text,
                    isRecording: isRecording,
                    currentTimestamp: currentTimestamp,
                    onTextChange: onTextChange
                )
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }
}

// MARK: - Markdown Preview for Notes

struct MarkdownNotesPreview: View {
    let text: String

    private var lines: [String] {
        text.components(separatedBy: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if text.isEmpty {
                    Text("No notes yet")
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        renderLine(line)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
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
        } else if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
            let checked = trimmed.hasPrefix("- [x] ")
            let content = String(trimmed.dropFirst(6))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.caption)
                    .foregroundColor(checked ? .green : .secondary)
                inlineMarkdown(content)
            }
            .padding(.leading, 12)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .padding(.top, 4)
                inlineMarkdown(String(trimmed.dropFirst(2)))
            }
            .padding(.leading, 12)
        } else if let dotIndex = trimmed.firstIndex(of: "."),
                  trimmed[trimmed.startIndex..<dotIndex].allSatisfy(\.isNumber),
                  !trimmed[trimmed.startIndex..<dotIndex].isEmpty,
                  trimmed.index(after: dotIndex) < trimmed.endIndex,
                  trimmed[trimmed.index(after: dotIndex)] == " " {
            let number = String(trimmed[...dotIndex])
            let content = String(trimmed[trimmed.index(dotIndex, offsetBy: 2)...])
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number)
                    .font(.body)
                    .foregroundColor(.secondary)
                inlineMarkdown(content)
            }
            .padding(.leading, 12)
        } else if trimmed.hasPrefix("[") && trimmed.contains("] ") {
            // Timestamped note line, e.g. [1:23] some text
            let parts = trimmed.split(separator: "] ", maxSplits: 1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(parts[0]) + "]")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                if parts.count > 1 {
                    inlineMarkdown(String(parts[1]))
                }
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 4)
        } else {
            inlineMarkdown(trimmed)
        }
    }

    private func inlineMarkdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        } else {
            return Text(text)
        }
    }
}

// MARK: - NSViewRepresentable for NSTextView with timestamp injection

struct TimestampedTextView: NSViewRepresentable {
    @Binding var text: String
    var isRecording: Bool
    var currentTimestamp: () -> String
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        // Placeholder
        textView.string = text
        if text.isEmpty {
            textView.string = ""
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self

        // Only update text if it changed externally (not from user typing)
        if textView.string != text && !context.coordinator.isUpdatingFromTextView {
            textView.string = text
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TimestampedTextView
        weak var textView: NSTextView?
        var isUpdatingFromTextView = false
        private var debounceWorkItem: DispatchWorkItem?

        init(_ parent: TimestampedTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isUpdatingFromTextView = true
            parent.text = textView.string
            isUpdatingFromTextView = false

            // Debounced auto-save
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.parent.onTextChange?()
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if parent.isRecording {
                    let timestamp = parent.currentTimestamp()
                    let insertion = "\n[\(timestamp)] "
                    textView.insertText(insertion, replacementRange: textView.selectedRange())
                    return true
                }
            }
            return false
        }
    }
}
