import AppKit

/// The row of open-file tabs above the editor.
final class TabBarView: NSView {
    struct Tab {
        let title: String
        let isDirty: Bool
        let toolTip: String?
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    private let stack = NSStackView()
    private let scroll = NSScrollView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(_ tabs: [Tab], selected: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, tab) in tabs.enumerated() {
            let item = TabItemView(tab: tab, isSelected: index == selected)
            item.onSelect = { [weak self] in self?.onSelect?(index) }
            item.onClose = { [weak self] in self?.onClose?(index) }
            stack.addArrangedSubview(item)
            item.heightAnchor.constraint(equalTo: stack.heightAnchor).isActive = true
        }
        if stack.arrangedSubviews.indices.contains(selected) {
            layoutSubtreeIfNeeded()
            stack.arrangedSubviews[selected].scrollToVisible(stack.arrangedSubviews[selected].bounds)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        Theme.separator.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private let isSelected: Bool
    private let isDirty: Bool
    private let closeButton = NSButton()

    init(tab: TabBarView.Tab, isSelected: Bool) {
        self.isSelected = isSelected
        self.isDirty = tab.isDirty
        super.init(frame: .zero)
        toolTip = tab.toolTip

        let label = NSTextField(labelWithString: tab.title)
        label.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Close"
        showCloseImage(hovering: false)

        let row = NSStackView(views: [label, closeButton])
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func showCloseImage(hovering: Bool) {
        let dot = isDirty && !hovering
        let configuration = NSImage.SymbolConfiguration(pointSize: dot ? 7 : 9, weight: .bold)
        closeButton.image = NSImage(systemSymbolName: dot ? "circle.fill" : "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(configuration)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.alphaValue = (isSelected || isDirty || hovering) ? 1 : 0.35
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { showCloseImage(hovering: true) }
    override func mouseExited(with event: NSEvent) { showCloseImage(hovering: false) }
    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func otherMouseDown(with event: NSEvent) { onClose?() }   // middle-click closes
    @objc private func closeClicked() { onClose?() }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            Theme.background.setFill()
            bounds.fill()
            Theme.accent.setFill()
            NSRect(x: 0, y: bounds.maxY - 2, width: bounds.width, height: 2).fill()
        }
        Theme.separator.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    override var isFlipped: Bool { false }
}
