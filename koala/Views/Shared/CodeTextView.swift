import SwiftUI
import AppKit

// MARK: - CodeTextView

struct CodeTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = AutoPairTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        weak var textView: NSTextView?

        init(_ parent: CodeTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - AutoPairTextView

private final class AutoPairTextView: NSTextView {

    private let openToClose: [Character: Character] = [
        "{": "}", "[": "]", "(": ")", "\"": "\""
    ]
    private let closingChars: Set<Character> = ["}", "]", ")", "\""]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let str = string as? String, str.count == 1,
              let ch = str.first else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        // Skip-over closing bracket if next char already matches
        if closingChars.contains(ch) {
            let sel = selectedRange()
            let nsStr = self.string as NSString
            if sel.location < nsStr.length {
                let nextChar = nsStr.character(at: sel.location)
                if let nextUniChar = Unicode.Scalar(nextChar), Character(nextUniChar) == ch {
                    setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                    return
                }
            }
        }

        // Auto-pair open brackets
        if let close = openToClose[ch] {
            let pair = "\(ch)\(close)"
            super.insertText(pair, replacementRange: replacementRange)
            let newSel = selectedRange()
            setSelectedRange(NSRange(location: newSel.location - 1, length: 0))
            return
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let nsStr = self.string as NSString
        let lineRange = nsStr.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineStr = nsStr.substring(with: lineRange)

        // Compute current line indentation
        var indent = ""
        for c in lineStr {
            if c == " " || c == "\t" { indent.append(c) } else { break }
        }

        // Check if char before cursor is { or [
        var extraIndent = ""
        if sel.location > 0 {
            let prevChar = nsStr.character(at: sel.location - 1)
            if let scalar = Unicode.Scalar(prevChar) {
                let c = Character(scalar)
                if c == "{" || c == "[" { extraIndent = "  " }
            }
        }

        super.insertNewline(sender)
        if !indent.isEmpty || !extraIndent.isEmpty {
            super.insertText(indent + extraIndent, replacementRange: selectedRange())
        }
    }
}
