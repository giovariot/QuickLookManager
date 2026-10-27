import AppKit

/// Righello con i numeri di riga (solo la prima riga visiva di ogni riga logica, come in Xcode).
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        NotificationCenter.default.addObserver(self, selector: #selector(needsRedraw), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(needsRedraw), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
    }
    required init(coder: NSCoder) { fatalError() }

    @objc private func needsRedraw() { needsDisplay = true }

    private var numberFont: NSFont {
        .monospacedDigitSystemFont(ofSize: max(9, (textView?.font?.pointSize ?? 12) - 1), weight: .regular)
    }

    private func updateThickness(lineCount: Int) {
        let digits = max(3, String(lineCount).count)
        let w = ("8" as NSString).size(withAttributes: [.font: numberFont]).width * CGFloat(digits) + 16
        if abs(ruleThickness - w) > 0.5 { ruleThickness = w }
    }

    /// Offset UTF-16 dell'inizio di ogni riga logica, calcolati una volta sola.
    private lazy var lineStarts: [Int] = {
        guard let ns = textView?.string as NSString? else { return [0] }
        var starts = [0]
        var i = 0
        let n = ns.length
        while i < n {
            let r = ns.lineRange(for: NSRange(location: i, length: 0))
            i = NSMaxRange(r)
            if i < n { starts.append(i) } else if r.length > 0, ns.character(at: n - 1) == 10 || ns.character(at: n - 1) == 13 { starts.append(n) }
        }
        return starts
    }()

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
        updateThickness(lineCount: lineStarts.count)

        let attrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor]
        let visible = tv.visibleRect
        let origin = tv.textContainerOrigin
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let firstChar = lm.characterIndexForGlyph(at: glyphRange.location)
        let lastChar = NSMaxRange(lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil))
        // prima riga logica che contiene firstChar
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if lineStarts[mid] <= firstChar { lo = mid } else { hi = mid - 1 } }
        var line = lo
        let length = (tv.string as NSString).length
        while line < lineStarts.count, lineStarts[line] <= lastChar {
            let start = lineStarts[line]
            var rectLine: NSRect
            if start < length {
                rectLine = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: start), effectiveRange: nil)
            } else {
                rectLine = lm.extraLineFragmentRect
                if rectLine.isEmpty { break }
            }
            let y = rectLine.minY + origin.y - visible.minY
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + (rectLine.height - size.height) / 2), withAttributes: attrs)
            line += 1
        }
    }
}

public enum CodeView {
    /// Vista scorrevole di sola lettura con testo attribuito e (opzionalmente) numeri di riga.
    public static func make(attributed: NSAttributedString, lineNumbers: Bool, wrap: Bool, tabWidth: Int = 4, notice: String? = nil) -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = !wrap
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = !wrap
        tv.autoresizingMask = wrap ? [.width] : []
        tv.textContainer?.widthTracksTextView = wrap
        tv.textContainer?.containerSize = NSSize(width: wrap ? 600 : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.layoutManager?.allowsNonContiguousLayout = true

        let m = NSMutableAttributedString(attributedString: attributed)
        if let font = attributed.length > 0 ? attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil {
            let ps = NSMutableParagraphStyle()
            ps.defaultTabInterval = ("8" as NSString).size(withAttributes: [.font: font]).width * CGFloat(tabWidth)
            ps.tabStops = []
            m.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: m.length))
        }
        if let notice {
            let font = NSFont.preferredFont(forTextStyle: .callout)
            m.append(NSAttributedString(string: "\n\n" + notice + "\n", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        tv.textStorage?.setAttributedString(m)
        tv.setAccessibilityLabel(String(localized: "Contenuto del file", bundle: QTLPaths.bundle))
        scroll.documentView = tv

        if lineNumbers {
            scroll.hasVerticalRuler = true
            scroll.verticalRulerView = LineNumberRulerView(textView: tv, scrollView: scroll)
            scroll.rulersVisible = true
        }
        return scroll
    }
}
