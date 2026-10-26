import AppKit

/// Menu items with a view in them: the title at the top, and the windows-per-row picker.
@MainActor
enum MenuViews {
    /// The width every view item asks for; the menu grows to its widest item.
    static let width: CGFloat = 270
    /// Where a menu item's text starts, past the checkmark column, so views line up with it.
    static let textInset: CGFloat = 28

    /// The menu's name, bold, like the title of a Control Center menu.
    static func title(_ text: String) -> NSMenuItem {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.sizeToFit()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        view.autoresizingMask = [.width]  // the menu stretches it to its own width
        label.frame.origin = NSPoint(x: textInset, y: ((view.bounds.height - label.frame.height) / 2).rounded())
        view.addSubview(label)
        let item = NSMenuItem()
        item.view = view
        return item
    }

    /// A row of numbers to pick from. Picking one keeps the menu open, so it's easy to try a few.
    static func picker(_ values: ClosedRange<Int>, selected: Int, onPick: @escaping (Int) -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = PickerView(values: values, selected: selected, onPick: onPick)
        return item
    }
}

private final class PickerView: NSView {
    private let values: ClosedRange<Int>
    private let onPick: (Int) -> Void

    init(values: ClosedRange<Int>, selected: Int, onPick: @escaping (Int) -> Void) {
        self.values = values
        self.onPick = onPick
        super.init(frame: NSRect(x: 0, y: 0, width: MenuViews.width, height: 36))
        autoresizingMask = [.width]  // the menu stretches it to its own width
        let control = NSSegmentedControl(
            labels: values.map(String.init), trackingMode: .selectOne, target: self, action: #selector(pick(_:)))
        control.segmentDistribution = .fillEqually
        control.selectedSegment = selected - values.lowerBound
        // From the text column to the separators' right end.
        control.frame = NSRect(
            x: MenuViews.textInset, y: 6, width: bounds.width - MenuViews.textInset - 14, height: bounds.height - 12)
        control.autoresizingMask = [.width]
        addSubview(control)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func pick(_ control: NSSegmentedControl) {
        onPick(values.lowerBound + control.selectedSegment)
    }
}
