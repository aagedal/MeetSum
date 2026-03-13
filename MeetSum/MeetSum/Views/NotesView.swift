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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Label("Notes", systemImage: "note.text")
                .font(.headline)

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
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
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
