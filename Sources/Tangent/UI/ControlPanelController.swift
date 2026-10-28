import AppKit

/// Interactive editor for a wallpaper's property controls.
///
/// Every change is pushed immediately through the page's property listener
/// (`window.tangentPropertyListener(name, value)`), and persisted by
/// `PropertyStore` so the value survives a relaunch. Built in AppKit rather than
/// SwiftUI because the Command Line Tools ship without SwiftUI macros.
final class ControlPanelController: NSWindowController, NSTextFieldDelegate {

    private let controls: [PropertyControl]
    private let root: URL
    private let onChange: (String, JSONValue) -> Void
    private let onReset: () -> Void

    private var valueLabels: [Int: NSTextField] = [:]
    private var steps: [Int: Double] = [:]

    init(
        title: String,
        controls: [PropertyControl],
        root: URL,
        onChange: @escaping (String, JSONValue) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.controls = controls
        self.root = root
        self.onChange = onChange
        self.onReset = onReset

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(title) Properties"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Do not hand the first text field focus (and a selection) on open;
        // the panel is for browsing values until the user clicks a control.
        window?.makeFirstResponder(nil)
    }

    // MARK: - Interface

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        for (index, control) in controls.enumerated() {
            stack.addArrangedSubview(row(for: index, control: control))
        }

        let divider = NSBox()
        divider.boxType = .separator

        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetPressed))
        reset.bezelStyle = .rounded
        reset.toolTip = "Discard customised values and restore the pack's original control defaults."

        stack.addArrangedSubview(divider)
        stack.addArrangedSubview(reset)

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = document

        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16),
        ])

        // Every row spans the stack so sliders and text boxes fill the panel.
        for row in stack.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if controls.isEmpty {
            let empty = NSTextField(labelWithString: "This wallpaper defines no controls.")
            empty.textColor = .secondaryLabelColor
            stack.insertArrangedSubview(empty, at: 0)
            empty.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func row(for index: Int, control: PropertyControl) -> NSView {
        switch control.spec {
        case .slider(_, let min, let max, let step, let value):
            let header = headerRow(index: index, title: control.spec.title, help: control.help)
            updateValueLabel(index, value: value)

            let slider = NSSlider(
                value: value,
                minValue: min,
                maxValue: max,
                target: self,
                action: #selector(sliderChanged(_:))
            )
            slider.tag = index
            slider.isContinuous = true
            if step > 0 {
                slider.altIncrementValue = step
            }
            steps[index] = step

            return verticalRow(top: header, bottom: slider)

        case .textbox(_, let value):
            let field = NSTextField(string: value)
            field.tag = index
            field.target = self
            field.action = #selector(textboxChanged(_:))
            field.delegate = self
            field.placeholderString = control.spec.title
            return verticalRow(
                top: headerRow(index: index, title: control.spec.title, help: control.help),
                bottom: field
            )

        case .dropdown(_, let items, let value):
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: items.isEmpty ? ["(no items)"] : items)
            if items.indices.contains(value) {
                popup.selectItem(at: value)
            }
            popup.tag = index
            popup.target = self
            popup.action = #selector(dropdownChanged(_:))
            return verticalRow(
                top: headerRow(index: index, title: control.spec.title, help: control.help),
                bottom: popup
            )

        case .folderDropdown(_, let filter, let folder, let value):
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            let directory = root.appendingPathComponent(folder)
            let options = PackProperties.folderOptions(folder: directory, filter: filter)
            popup.addItem(withTitle: "(None)")
            popup.addItems(withTitles: options)
            if let selected = options.firstIndex(of: value) {
                popup.selectItem(at: selected + 1)
            }
            popup.tag = index
            popup.target = self
            popup.action = #selector(folderChanged(_:))
            return verticalRow(
                top: headerRow(index: index, title: control.spec.title, help: control.help),
                bottom: popup
            )

        case .checkbox(_, let value):
            let box = NSButton(
                checkboxWithTitle: control.spec.title,
                target: self,
                action: #selector(checkboxChanged(_:))
            )
            box.tag = index
            box.state = value ? .on : .off
            box.toolTip = control.help
            return verticalRow(top: box, bottom: nil)

        case .button(let text, _):
            let button = NSButton(
                title: text.isEmpty ? control.spec.title : text,
                target: self,
                action: #selector(buttonPressed(_:))
            )
            button.bezelStyle = .rounded
            button.tag = index
            button.toolTip = control.help
            // The button's own label is the control's `text`; a header would
            // just repeat it.
            return verticalRow(top: button, bottom: nil)

        case .label(let text):
            let label = NSTextField(wrappingLabelWithString: text.isEmpty ? control.spec.title : text)
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 11)
            label.toolTip = control.help
            return verticalRow(top: label, bottom: nil)

        case .color(_, let value):
            let header = headerRow(index: index, title: control.spec.title, help: control.help)
            let well = NSColorWell()
            well.color = NSColor(hexColor: value) ?? .white
            well.tag = index
            well.target = self
            well.action = #selector(colorChanged(_:))

            let container = NSView()
            container.addSubview(header)
            container.addSubview(well)
            header.translatesAutoresizingMaskIntoConstraints = false
            well.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: container.topAnchor),
                header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                header.trailingAnchor.constraint(equalTo: container.trailingAnchor),

                well.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
                well.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                well.widthAnchor.constraint(equalToConstant: 44),
                well.heightAnchor.constraint(equalToConstant: 24),
                well.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            return container
        }
    }

    /// A title row plus a control underneath, wired for width-filling.
    private func verticalRow(top: NSView, bottom: NSView?) -> NSView {
        let container = NSView()
        top.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(top)

        var constraints: [NSLayoutConstraint] = [
            top.topAnchor.constraint(equalTo: container.topAnchor),
        ]

        if let bottom {
            bottom.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(bottom)
            constraints += [
                top.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                top.trailingAnchor.constraint(equalTo: container.trailingAnchor),

                bottom.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 6),
                bottom.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bottom.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ]
            // Buttons and colour wells keep their intrinsic width; sliders,
            // popups and text fields stretch to the panel width.
            if !(bottom is NSButton) && !(bottom is NSColorWell) {
                constraints.append(bottom.trailingAnchor.constraint(equalTo: container.trailingAnchor))
            }
        } else {
            constraints += [
                top.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                top.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                top.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func headerRow(index: Int, title: String, help: String?) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = help

        let value = NSTextField(labelWithString: "")
        value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabels[index] = value

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func updateValueLabel(_ index: Int, value: Double) {
        valueLabels[index]?.stringValue = Self.format(value)
    }

    private static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e9 {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) {
        let index = sender.tag
        var value = sender.doubleValue
        if let step = steps[index], step > 0 {
            value = (value / step).rounded() * step
            sender.doubleValue = value
        }
        updateValueLabel(index, value: value)
        push(.number(value), at: index)
    }

    @objc private func textboxChanged(_ sender: NSTextField) {
        push(.string(sender.stringValue), at: sender.tag)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let control = controls[safe: field.tag],
              case .textbox = control.spec
        else { return }
        push(.string(field.stringValue), at: field.tag)
    }

    @objc private func dropdownChanged(_ sender: NSPopUpButton) {
        push(.number(Double(sender.indexOfSelectedItem)), at: sender.tag)
    }

    @objc private func folderChanged(_ sender: NSPopUpButton) {
        let index = sender.tag
        guard index >= 0, index < controls.count else { return }
        if sender.indexOfSelectedItem <= 0 {
            push(.null, at: index)
            return
        }
        let name = sender.titleOfSelectedItem ?? ""
        push(name.isEmpty ? .null : .string(name), at: index)
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        push(.bool(sender.state == .on), at: sender.tag)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        push(.string(sender.color.hexColor), at: sender.tag)
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        // A button always sends `true`, never its configured `value`.
        push(.bool(true), at: sender.tag)
    }

    @objc private func resetPressed() {
        onReset()
    }

    private func push(_ value: JSONValue, at index: Int) {
        guard let control = controls[safe: index] else { return }
        onChange(control.name, value)
    }
}

// MARK: - Helpers

/// Document view for the scroll view; `isFlipped` keeps content anchored to the
/// top instead of the bottom.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension NSColor {
    /// Parses `#RGB`, `#RRGGBB` and `#RRGGBBAA`, the format colour controls
    /// use.
    convenience init?(hexColor: String) {
        var text = hexColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8,
              let value = UInt32(text, radix: 16)
        else { return nil }

        let hasAlpha = text.count == 8
        let red = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// `#RRGGBB`, matching the control format.
    var hexColor: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
