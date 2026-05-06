import SwiftUI
import AppKit

/// Markdown editing actions exposed by the source-pane toolbar.
///
/// Every case routes through `NSTextView.shouldChangeText/replaceCharacters/
/// didChangeText` so the operation is registered as a proper undo group on the
/// text view's own undo manager.
enum MdEdit: String, Hashable, CaseIterable {
    case heading
    case bold
    case italic
    case strikethrough
    case link
    case inlineCode
    case codeBlock
    case bulletList
    case numberedList
    case taskList
    case quote
    case horizontalRule

    /// Order shown in the toolbar.
    static let toolbar: [MdEdit] = [
        .heading, .bold, .italic, .strikethrough,
        .link, .inlineCode, .codeBlock,
        .bulletList, .numberedList, .taskList,
        .quote, .horizontalRule,
    ]

    var help: String {
        switch self {
        case .heading:        return "Heading"
        case .bold:           return "Bold"
        case .italic:         return "Italic"
        case .strikethrough:  return "Strikethrough"
        case .link:           return "Link"
        case .inlineCode:     return "Inline code"
        case .codeBlock:      return "Code block"
        case .bulletList:     return "Bullet list"
        case .numberedList:   return "Numbered list"
        case .taskList:       return "Task list"
        case .quote:          return "Quote"
        case .horizontalRule: return "Horizontal rule"
        }
    }

    /// Toolbar icon. SF Symbols where they exist; small text labels otherwise.
    @ViewBuilder var iconView: some View {
        switch self {
        case .heading:        Text("H").font(.system(size: 13, weight: .semibold))
        case .bold:           Image(systemName: "bold")
        case .italic:         Image(systemName: "italic")
        case .strikethrough:  Image(systemName: "strikethrough")
        case .link:           Image(systemName: "link")
        case .inlineCode:     Image(systemName: "chevron.left.forwardslash.chevron.right")
        case .codeBlock:      Image(systemName: "curlybraces")
        case .bulletList:     Image(systemName: "list.bullet")
        case .numberedList:   Image(systemName: "list.number")
        case .taskList:       Image(systemName: "checklist")
        case .quote:          Image(systemName: "text.quote")
        case .horizontalRule: Text("—").font(.system(size: 14, weight: .regular))
        }
    }

    // MARK: Apply

    func perform(on tv: NSTextView) {
        switch self {
        case .heading:        Self.prefixLine(tv, prefix: "## ")
        case .bulletList:     Self.prefixLine(tv, prefix: "- ")
        case .numberedList:   Self.prefixLine(tv, prefix: "1. ")
        case .taskList:       Self.prefixLine(tv, prefix: "- [ ] ")
        case .quote:          Self.prefixLine(tv, prefix: "> ")

        case .bold:           Self.wrap(tv, before: "**", after: "**", placeholder: "bold")
        case .italic:         Self.wrap(tv, before: "_",  after: "_",  placeholder: "italic")
        case .strikethrough:  Self.wrap(tv, before: "~~", after: "~~", placeholder: "strike")
        case .inlineCode:     Self.wrap(tv, before: "`",  after: "`",  placeholder: "code")
        case .link:           Self.wrapLink(tv)

        case .codeBlock:      Self.insertBlock(tv, body: "```\n\n```", caretLineOffset: 1)
        case .horizontalRule: Self.insertBlock(tv, body: "---", caretLineOffset: nil)
        }
    }

    // MARK: Building blocks
    //
    // All edits use the canonical NSTextView editing flow:
    //   1. `shouldChangeText(in:replacementString:)` to begin an undo group
    //   2. mutate `textStorage` via `replaceCharacters(in:with:)`
    //   3. `didChangeText()` to close the group
    // This is what keeps undo/redo intact and prevents the EXC_BAD_ACCESS
    // we saw when the binding-driven `tv.string = ...` path was registering
    // undo entries pointing at stale Swift closures.

    private static func wrap(_ tv: NSTextView,
                             before: String,
                             after: String,
                             placeholder: String) {
        let storage = tv.string as NSString
        var sel = tv.selectedRange()
        if sel.location > storage.length { sel = NSRange(location: storage.length, length: 0) }

        let selectedText: String = sel.length > 0
            ? storage.substring(with: sel)
            : placeholder
        let replacement = before + selectedText + after

        guard tv.shouldChangeText(in: sel, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: sel, with: replacement)
        tv.didChangeText()

        if sel.length == 0 {
            // Select the placeholder so the user can immediately type over it.
            let start = sel.location + (before as NSString).length
            tv.setSelectedRange(NSRange(location: start, length: (placeholder as NSString).length))
        } else {
            // Place the caret right after the wrapped text.
            let end = sel.location + (replacement as NSString).length
            tv.setSelectedRange(NSRange(location: end, length: 0))
        }
    }

    /// Link is a special wrap: when there's a selection, it becomes the link
    /// text and the caret lands inside `(url)`. Empty selection drops a full
    /// `[text](url)` template with `text` selected.
    private static func wrapLink(_ tv: NSTextView) {
        let storage = tv.string as NSString
        var sel = tv.selectedRange()
        if sel.location > storage.length { sel = NSRange(location: storage.length, length: 0) }

        if sel.length > 0 {
            let text = storage.substring(with: sel)
            let replacement = "[\(text)](url)"
            guard tv.shouldChangeText(in: sel, replacementString: replacement) else { return }
            tv.textStorage?.replaceCharacters(in: sel, with: replacement)
            tv.didChangeText()
            // Select the "url" placeholder
            let urlStart = sel.location + (text as NSString).length + 3   // "[\(text)]("
            tv.setSelectedRange(NSRange(location: urlStart, length: 3))    // "url"
        } else {
            let replacement = "[text](url)"
            guard tv.shouldChangeText(in: sel, replacementString: replacement) else { return }
            tv.textStorage?.replaceCharacters(in: sel, with: replacement)
            tv.didChangeText()
            // Select "text"
            tv.setSelectedRange(NSRange(location: sel.location + 1, length: 4))
        }
    }

    /// Insert `prefix` at the start of the line containing the caret.
    /// The caret position is preserved (shifted by the prefix length).
    private static func prefixLine(_ tv: NSTextView, prefix: String) {
        let storage = tv.string as NSString
        let sel = tv.selectedRange()
        let lineRange = storage.lineRange(for: NSRange(location: min(sel.location, storage.length),
                                                        length: 0))
        let insertRange = NSRange(location: lineRange.location, length: 0)

        guard tv.shouldChangeText(in: insertRange, replacementString: prefix) else { return }
        tv.textStorage?.replaceCharacters(in: insertRange, with: prefix)
        tv.didChangeText()

        let prefixLen = (prefix as NSString).length
        tv.setSelectedRange(NSRange(location: sel.location + prefixLen, length: sel.length))
    }

    /// Insert a self-contained block at the start of the current line. If the
    /// current line has content, a blank line is added before; a blank line is
    /// always appended after.
    ///
    /// `caretLineOffset` (when non-nil) is the line offset (from the inserted
    /// block's start) where the caret should land — used by the code-block
    /// action to drop the user inside the fences.
    private static func insertBlock(_ tv: NSTextView,
                                     body: String,
                                     caretLineOffset: Int?) {
        let storage = tv.string as NSString
        let sel = tv.selectedRange()
        let location = min(sel.location, storage.length)
        let lineRange = storage.lineRange(for: NSRange(location: location, length: 0))

        // Decide whether we need a leading newline (current line has content).
        let lineText = storage.substring(with: lineRange)
        let lineIsBlank = lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let leading  = lineIsBlank ? "" : "\n"
        let trailing = "\n"

        let insertRange = NSRange(location: lineIsBlank ? lineRange.location : lineRange.upperBound,
                                  length: 0)
        let replacement = leading + body + trailing

        guard tv.shouldChangeText(in: insertRange, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: insertRange, with: replacement)
        tv.didChangeText()

        if let offset = caretLineOffset {
            // Position caret on a specific line of the inserted block.
            let lines = (leading + body).components(separatedBy: "\n")
            let safeOffset = min(offset, lines.count - 1)
            var pos = insertRange.location
            for i in 0..<safeOffset {
                pos += (lines[i] as NSString).length + 1
            }
            tv.setSelectedRange(NSRange(location: pos, length: 0))
        } else {
            let end = insertRange.location + (replacement as NSString).length
            tv.setSelectedRange(NSRange(location: end, length: 0))
        }
    }
}
