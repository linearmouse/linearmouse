// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Defaults
import Foundation
import LaunchAtLogin
import OSLog

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var released = true
    private var showInDockTask: Task<Void, Never>?

    private func initWindowIfNeeded() {
        guard released else {
            return
        }

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 1160, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.delegate = self
        window.title = String(format: NSLocalizedString("%@ Rules", comment: ""), LinearMouse.appName)

        window.minSize = NSSize(width: 1040, height: 680)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
        let toolbar = NSToolbar(identifier: SettingsWindowToolbarItemIdentifier.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.contentViewController = RulesPrototypeHostingController()

        window.center()

        self.window = window
        released = false

        startShowInDockTask()
    }

    private func startShowInDockTask() {
        showInDockTask = Task {
            for await value in Defaults.updates(.showInDock, initial: true) {
                if value {
                    NSApplication.shared.setActivationPolicy(.regular)
                } else {
                    NSApplication.shared.setActivationPolicy(.accessory)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }

            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    private func stopShowInDockTask() {
        showInDockTask?.cancel()
        showInDockTask = nil
    }

    func bringToFront() {
        initWindowIfNeeded()

        guard let window else {
            return
        }

        window.bringToFront()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        stopShowInDockTask()
        released = true
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [SettingsWindowToolbarItemIdentifier.general, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [SettingsWindowToolbarItemIdentifier.general, .flexibleSpace]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == SettingsWindowToolbarItemIdentifier.general else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = NSLocalizedString("General", comment: "")
        item.paletteLabel = NSLocalizedString("General", comment: "")
        item.toolTip = NSLocalizedString("General Settings", comment: "")
        item.image = settingsToolbarSymbolImage("gearshape")
        item.isBordered = true
        if #available(macOS 11.0, *) {
            item.isNavigational = true
        }
        item.target = self
        item.action = #selector(showGeneralSettingsFromToolbar)
        return item
    }

    @objc private func showGeneralSettingsFromToolbar() {
        window?.contentViewController?.presentAsSheet(GeneralSettingsViewController())
    }
}

private enum SettingsWindowToolbarItemIdentifier {
    static let toolbar = "LinearMouse.SettingsWindowToolbar"
    static let general = NSToolbarItem.Identifier("LinearMouse.SettingsWindowToolbar.General")
}

private func settingsToolbarSymbolImage(_ name: String) -> NSImage? {
    if #available(macOS 11.0, *) {
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
    return NSImage(named: NSImage.actionTemplateName)
}

// MARK: - Root

private final class RulesSettingsViewController: NSSplitViewController {
    private let rulesListViewController = RulesListViewController()
    private let ruleDetailViewController = RuleDetailViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        rulesListViewController.delegate = self

        let sidebar = NSSplitViewItem(sidebarWithViewController: rulesListViewController)
        sidebar.canCollapse = false
        sidebar.minimumThickness = 290
        sidebar.maximumThickness = 340
        if #available(macOS 11.0, *) {
            sidebar.allowsFullHeightLayout = true
        }
        addSplitViewItem(sidebar)

        let detail = NSSplitViewItem(viewController: ruleDetailViewController)
        detail.minimumThickness = 640
        addSplitViewItem(detail)

        selectInitialRule()
    }

    private func selectInitialRule() {
        if ConfigurationState.shared.configuration.schemes.isEmpty {
            ruleDetailViewController.selectedRuleIndex = nil
        } else {
            rulesListViewController.selectRule(at: 0)
            ruleDetailViewController.selectedRuleIndex = 0
        }
    }
}

extension RulesSettingsViewController: RulesListViewControllerDelegate {
    func rulesListViewController(_: RulesListViewController, didSelectRuleAt index: Int?) {
        ruleDetailViewController.selectedRuleIndex = index
    }
}

// MARK: - Rules list

private protocol RulesListViewControllerDelegate: AnyObject {
    func rulesListViewController(_ controller: RulesListViewController, didSelectRuleAt index: Int?)
}

private final class RulesListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: RulesListViewControllerDelegate?

    private let configurationState = ConfigurationState.shared
    private let deviceState = DeviceState.shared
    private let tableView = NSTableView()
    private let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let deleteButton = NSButton(title: NSLocalizedString("Delete", comment: ""), target: nil, action: nil)
    private let duplicateButton = NSButton(title: NSLocalizedString("Duplicate", comment: ""), target: nil, action: nil)
    private let moveUpButton = NSButton(title: NSLocalizedString("Move Up", comment: ""), target: nil, action: nil)
    private let moveDownButton = NSButton(title: NSLocalizedString("Move Down", comment: ""), target: nil, action: nil)
    private let generalButton = NSButton(title: NSLocalizedString("General…", comment: ""), target: nil, action: nil)
    private let footerStatusLabel = NSTextField(labelWithString: "")

    private var subscriptions = Set<AnyCancellable>()

    private var selectedRuleIndex: Int? {
        let row = tableView.selectedRow
        guard row >= 0, row < rules.count else {
            return nil
        }
        return row
    }

    private var rules: [Scheme] {
        configurationState.configuration.schemes
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildView()
        bindState()
        updateButtons()
    }

    func selectRule(at index: Int) {
        guard index >= 0, index < rules.count else {
            tableView.deselectAll(nil)
            delegate?.rulesListViewController(self, didSelectRuleAt: nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        updateButtons()
    }

    private func buildView() {
        let root = verticalStack(spacing: 0)
        root.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.addSubview(root)
        pin(root, to: view)

        let header = verticalStack(spacing: 5)
        header.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
        header.addArrangedSubview(makeLabel(NSLocalizedString("Rules", comment: ""), size: 22, weight: .semibold))
        let subtitle = makeLabel(
            NSLocalizedString(
                "Matching rules apply from top to bottom. Later rules can replace earlier values.",
                comment: ""
            ),
            color: .secondaryLabelColor
        )
        subtitle.lineBreakMode = .byWordWrapping
        header.addArrangedSubview(subtitle)
        root.addArrangedSubview(header)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.rowHeight = 64
        tableView.selectionHighlightStyle = .sourceList
        if #available(macOS 11.0, *) {
            tableView.style = .sourceList
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Rule"))
        column.isEditable = false
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scrollView)

        let footer = verticalStack(spacing: 8)
        footer.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 14, right: 12)

        configureAddMenu()
        addButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteRule)
        duplicateButton.target = self
        duplicateButton.action = #selector(duplicateRule)
        moveUpButton.target = self
        moveUpButton.action = #selector(moveRuleUp)
        moveDownButton.target = self
        moveDownButton.action = #selector(moveRuleDown)
        generalButton.target = self
        generalButton.action = #selector(showGeneralSettings)

        let firstRow = horizontalStack(spacing: 8)
        firstRow.addArrangedSubview(addButton)
        firstRow.addArrangedSubview(deleteButton)
        firstRow.addArrangedSubview(duplicateButton)
        firstRow.addArrangedSubview(makeFlexibleSpace())

        let secondRow = horizontalStack(spacing: 8)
        secondRow.addArrangedSubview(moveUpButton)
        secondRow.addArrangedSubview(moveDownButton)
        secondRow.addArrangedSubview(makeFlexibleSpace())
        secondRow.addArrangedSubview(generalButton)

        footerStatusLabel.textColor = .secondaryLabelColor
        footerStatusLabel.font = .systemFont(ofSize: 11)
        footerStatusLabel.lineBreakMode = .byWordWrapping

        footer.addArrangedSubview(firstRow)
        footer.addArrangedSubview(secondRow)
        footer.addArrangedSubview(footerStatusLabel)
        root.addArrangedSubview(footer)
    }

    private func bindState() {
        configurationState.$configuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                let previousSelection = self.selectedRuleIndex
                self.tableView.reloadData()
                if let previousSelection, previousSelection < self.rules.count {
                    self.selectRule(at: previousSelection)
                } else if !self.rules.isEmpty {
                    self.selectRule(at: max(0, self.rules.count - 1))
                } else {
                    self.delegate?.rulesListViewController(self, didSelectRuleAt: nil)
                }
                self.updateButtons()
            }
            .store(in: &subscriptions)

        deviceState.$currentDeviceRef
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &subscriptions)

        ScreenManager.shared
            .$currentScreenName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &subscriptions)
    }

    private func configureAddMenu() {
        addButton.removeAllItems()
        addButton.addItem(withTitle: NSLocalizedString("Add Rule…", comment: ""))

        let menuItems: [(String, AddRuleKind)] = [
            (NSLocalizedString("Global Rule", comment: ""), .global),
            (NSLocalizedString("All Mice Rule", comment: ""), .allMice),
            (NSLocalizedString("All Trackpads Rule", comment: ""), .allTrackpads),
            (NSLocalizedString("Current Device Rule", comment: ""), .currentDevice),
            (NSLocalizedString("Frontmost App Rule", comment: ""), .frontmostApp),
            (NSLocalizedString("Current Display Rule", comment: ""), .currentDisplay),
            (NSLocalizedString("Empty Conditional Rule", comment: ""), .emptyConditional)
        ]

        for (title, kind) in menuItems {
            let item = NSMenuItem(title: title, action: #selector(addRuleFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind
            addButton.menu?.addItem(item)
        }
    }

    private func updateButtons() {
        let hasSelection = selectedRuleIndex != nil
        deleteButton.isEnabled = hasSelection
        duplicateButton.isEnabled = hasSelection
        moveUpButton.isEnabled = (selectedRuleIndex ?? 0) > 0
        moveDownButton.isEnabled = selectedRuleIndex.map { $0 < rules.count - 1 } ?? false
        footerStatusLabel.stringValue = String(
            format: NSLocalizedString(
                "%d rule(s). Active rules are marked with a dot for the current device, app, and display.",
                comment: ""
            ),
            rules.count
        )
    }

    @objc private func addRuleFromMenu(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? AddRuleKind else {
            return
        }

        var scheme: Scheme
        switch kind {
        case .global:
            scheme = Scheme()
        case .allMice:
            scheme = Scheme(if: [.init(device: .init(category: [.mouse]))])
        case .allTrackpads:
            scheme = Scheme(if: [.init(device: .init(category: [.trackpad]))])
        case .currentDevice:
            if let device = DeviceState.shared.currentDeviceRef?.value {
                scheme = Scheme(if: [.init(device: .init(of: device))])
            } else {
                scheme = Scheme(if: [.init(device: .init(category: [.mouse]))])
            }
        case .frontmostApp:
            if let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                scheme = Scheme(if: [.init(app: bundleIdentifier)])
            } else {
                scheme = Scheme(if: [.init()])
            }
        case .currentDisplay:
            scheme = Scheme(if: [.init(display: ScreenManager.shared.currentScreenName)])
        case .emptyConditional:
            scheme = Scheme(if: [.init()])
        }

        var configuration = configurationState.configuration
        let insertIndex = selectedRuleIndex.map { $0 + 1 } ?? configuration.schemes.endIndex
        configuration.schemes.insert(scheme, at: insertIndex)
        configurationState.configuration = configuration
        selectRule(at: insertIndex)
    }

    @objc private func deleteRule() {
        guard let index = selectedRuleIndex else {
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete Rule?", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("This will delete “%@” and all settings stored in that rule.", comment: ""),
            RulePresenter.title(for: rules[index], at: index)
        )
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        var configuration = configurationState.configuration
        configuration.schemes.remove(at: index)
        configurationState.configuration = configuration
        if configuration.schemes.isEmpty {
            tableView.deselectAll(nil)
            delegate?.rulesListViewController(self, didSelectRuleAt: nil)
        } else {
            selectRule(at: min(index, configuration.schemes.count - 1))
        }
    }

    @objc private func duplicateRule() {
        guard let index = selectedRuleIndex else {
            return
        }

        var configuration = configurationState.configuration
        configuration.schemes.insert(configuration.schemes[index], at: index + 1)
        configurationState.configuration = configuration
        selectRule(at: index + 1)
    }

    @objc private func moveRuleUp() {
        moveSelectedRule(by: -1)
    }

    @objc private func moveRuleDown() {
        moveSelectedRule(by: 1)
    }

    private func moveSelectedRule(by offset: Int) {
        guard let index = selectedRuleIndex else {
            return
        }
        let destination = index + offset
        guard destination >= 0, destination < rules.count else {
            return
        }

        var configuration = configurationState.configuration
        configuration.schemes.swapAt(index, destination)
        configurationState.configuration = configuration
        selectRule(at: destination)
    }

    @objc private func showGeneralSettings() {
        guard let parent = view.window?.contentViewController else {
            return
        }
        parent.presentAsSheet(GeneralSettingsViewController())
    }

    func numberOfRows(in _: NSTableView) -> Int {
        rules.count
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let scheme = rules[row]
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("RuleCell")

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 8

        let number = makePill("#\(row + 1)")
        let title = makeLabel(RulePresenter.title(for: scheme, at: row), weight: .semibold)
        let summary = makeLabel(RulePresenter.summary(for: scheme), color: .secondaryLabelColor)
        let changes = makeLabel(RulePresenter.changesSummary(for: scheme), size: 11, color: .secondaryLabelColor)
        changes.lineBreakMode = .byTruncatingTail

        let text = verticalStack(spacing: 2)
        text.addArrangedSubview(title)
        text.addArrangedSubview(summary)
        text.addArrangedSubview(changes)

        let rowStack = horizontalStack(spacing: 9)
        rowStack.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 10)
        rowStack.addArrangedSubview(number)
        rowStack.addArrangedSubview(text)
        rowStack.addArrangedSubview(makeFlexibleSpace())
        if RulePresenter.isActiveNow(scheme) {
            rowStack.addArrangedSubview(makeStatusDot())
        }

        wrapper.addSubview(rowStack)
        pin(rowStack, to: wrapper)
        cell.addSubview(wrapper)
        pin(wrapper, to: cell, inset: NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        delegate?.rulesListViewController(self, didSelectRuleAt: selectedRuleIndex)
        updateButtons()
    }
}

private enum AddRuleKind {
    case global
    case allMice
    case allTrackpads
    case currentDevice
    case frontmostApp
    case currentDisplay
    case emptyConditional
}

// MARK: - Rule detail

private final class RuleDetailViewController: NSViewController, NSTextFieldDelegate {
    var selectedRuleIndex: Int? {
        didSet {
            reload()
        }
    }

    private let configurationState = ConfigurationState.shared
    private let contentStack = verticalStack(spacing: 18)
    private var jsonTextView: NSTextView?
    private var subscriptions = Set<AnyCancellable>()

    private var selectedScheme: Scheme? {
        guard let selectedRuleIndex,
              selectedRuleIndex >= 0,
              selectedRuleIndex < configurationState.configuration.schemes.count else {
            return nil
        }
        return configurationState.configuration.schemes[selectedRuleIndex]
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildView()
        bindState()
        reload()
    }

    private func buildView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 28, right: 28)
        scrollView.documentView = contentStack

        view.addSubview(scrollView)
        pin(scrollView, to: view)
        contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
    }

    private func bindState() {
        configurationState.$configuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &subscriptions)

        deviceStatePublishers()
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &subscriptions)
    }

    private func deviceStatePublishers() -> AnyPublisher<Void, Never> {
        let device = DeviceState.shared.$currentDeviceRef.map { _ in () }.eraseToAnyPublisher()
        let screen = ScreenManager.shared.$currentScreenName.map { _ in () }.eraseToAnyPublisher()
        return device.merge(with: screen).eraseToAnyPublisher()
    }

    private func reload() {
        guard isViewLoaded else {
            return
        }

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        jsonTextView = nil

        guard let selectedRuleIndex,
              let scheme = selectedScheme else {
            contentStack.addArrangedSubview(makeEmptyState())
            return
        }

        contentStack.addArrangedSubview(makeHeader(for: scheme, at: selectedRuleIndex))
        contentStack.addArrangedSubview(makeConditionsSection(for: scheme))
        contentStack.addArrangedSubview(makeSettingsSection(for: scheme))
        contentStack.addArrangedSubview(makeEffectiveValuesSection())
        contentStack.addArrangedSubview(makeActiveChainSection())
        contentStack.addArrangedSubview(makeJSONSection(for: scheme))
    }

    private func makeEmptyState() -> NSView {
        let stack = verticalStack(spacing: 10)
        stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: 120, left: 40, bottom: 40, right: 40)
        stack.addArrangedSubview(makeLabel(
            NSLocalizedString("No Rule Selected", comment: ""),
            size: 22,
            weight: .semibold
        ))
        let message = makeLabel(
            NSLocalizedString("Add a rule to define where pointer, scrolling, and button settings apply.", comment: ""),
            color: .secondaryLabelColor
        )
        message.alignment = .center
        stack.addArrangedSubview(message)
        return stack
    }

    private func makeHeader(for scheme: Scheme, at index: Int) -> NSView {
        let root = verticalStack(spacing: 10)

        let top = horizontalStack(spacing: 12)
        let titleStack = verticalStack(spacing: 4)
        titleStack.addArrangedSubview(makeLabel(
            RulePresenter.title(for: scheme, at: index),
            size: 24,
            weight: .semibold
        ))
        let subtitle = makeLabel(
            RulePresenter.summary(for: scheme),
            color: .secondaryLabelColor
        )
        subtitle.lineBreakMode = .byWordWrapping
        titleStack.addArrangedSubview(subtitle)

        top.addArrangedSubview(titleStack)
        top.addArrangedSubview(makeFlexibleSpace())
        top.addArrangedSubview(makePill(
            RulePresenter.isActiveNow(scheme) ? NSLocalizedString("Active Now", comment: "") : NSLocalizedString(
                "Inactive Now",
                comment: ""
            ),
            accent: RulePresenter.isActiveNow(scheme)
        ))

        root.addArrangedSubview(top)

        let note = makeNoteBox(
            NSLocalizedString(
                "Rules are stored in the same order as the configuration file. Matching rules apply from top to bottom; a later rule only replaces values it explicitly sets.",
                comment: ""
            )
        )
        root.addArrangedSubview(note)

        return root
    }

    private func makeConditionsSection(for scheme: Scheme) -> NSView {
        let section = makeSection(title: NSLocalizedString("When", comment: ""))

        let conditions = scheme.if ?? []
        if conditions.isEmpty {
            let row = horizontalStack(spacing: 10)
            row.addArrangedSubview(makePill(NSLocalizedString("Always", comment: ""), accent: true))
            row.addArrangedSubview(makeLabel(
                NSLocalizedString("This is a global rule and matches every context.", comment: ""),
                color: .secondaryLabelColor
            ))
            row.addArrangedSubview(makeFlexibleSpace())
            section.content.addArrangedSubview(row)
        } else {
            if conditions.count > 1 {
                section.content.addArrangedSubview(makeNoteBox(NSLocalizedString(
                    "This rule has multiple condition groups. It matches when any group matches.",
                    comment: ""
                )))
            }

            for (groupIndex, condition) in conditions.enumerated() {
                section.content.addArrangedSubview(makeConditionGroup(
                    condition,
                    groupIndex: groupIndex,
                    groupCount: conditions.count
                ))
            }
        }

        let addRow = horizontalStack(spacing: 8)
        let addConditionButton = NSPopUpButton(frame: .zero, pullsDown: true)
        addConditionButton.addItem(withTitle: NSLocalizedString("Add Condition…", comment: ""))
        let items: [(String, RuleConditionKind)] = [
            (NSLocalizedString("Device", comment: ""), .device),
            (NSLocalizedString("App", comment: ""), .app),
            (NSLocalizedString("Parent App", comment: ""), .parentApp),
            (NSLocalizedString("Process Group App", comment: ""), .groupApp),
            (NSLocalizedString("Process Name", comment: ""), .processName),
            (NSLocalizedString("Process Path", comment: ""), .processPath),
            (NSLocalizedString("Display", comment: ""), .display)
        ]
        for (title, kind) in items {
            let item = NSMenuItem(title: title, action: #selector(addCondition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind
            addConditionButton.menu?.addItem(item)
        }
        addRow.addArrangedSubview(addConditionButton)
        addRow.addArrangedSubview(makeFlexibleSpace())
        section.content.addArrangedSubview(addRow)

        return section.view
    }

    private func makeConditionGroup(_ condition: Scheme.If, groupIndex: Int, groupCount: Int) -> NSView {
        let wrapper = verticalStack(spacing: 10)
        wrapper.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 8
        wrapper.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        if groupCount > 1 {
            wrapper.addArrangedSubview(makeLabel(
                String(format: NSLocalizedString("Condition Group %d", comment: ""), groupIndex + 1),
                weight: .semibold
            ))
        }

        wrapper.addArrangedSubview(makeDeviceConditionRow(condition.device, groupIndex: groupIndex))

        if condition.app != nil {
            wrapper.addArrangedSubview(makeTextConditionRow(
                title: NSLocalizedString("App", comment: ""),
                value: condition.app,
                key: .app,
                groupIndex: groupIndex
            ))
        }
        if condition.parentApp != nil {
            wrapper.addArrangedSubview(makeTextConditionRow(
                title: NSLocalizedString("Parent App", comment: ""),
                value: condition.parentApp,
                key: .parentApp,
                groupIndex: groupIndex
            ))
        }
        if condition.groupApp != nil {
            wrapper.addArrangedSubview(makeTextConditionRow(
                title: NSLocalizedString("Process Group App", comment: ""),
                value: condition.groupApp,
                key: .groupApp,
                groupIndex: groupIndex
            ))
        }
        if condition.processName != nil {
            wrapper.addArrangedSubview(makeTextConditionRow(
                title: NSLocalizedString("Process Name", comment: ""),
                value: condition.processName,
                key: .processName,
                groupIndex: groupIndex
            ))
        }
        if condition.processPath != nil {
            wrapper.addArrangedSubview(makeTextConditionRow(
                title: NSLocalizedString("Process Path", comment: ""),
                value: condition.processPath,
                key: .processPath,
                groupIndex: groupIndex
            ))
        }
        if condition.display != nil {
            wrapper.addArrangedSubview(makeTextConditionRow(
                title: NSLocalizedString("Display", comment: ""),
                value: condition.display,
                key: .display,
                groupIndex: groupIndex
            ))
        }

        if condition.usesProcessCondition {
            wrapper.addArrangedSubview(makeNoteBox(NSLocalizedString(
                "Process conditions are matched against the frontmost or event-target process. They do not detect child processes running inside a terminal window.",
                comment: ""
            )))
        }

        return wrapper
    }

    private func makeDeviceConditionRow(_ matcher: DeviceMatcher?, groupIndex: Int) -> NSView {
        let row = horizontalStack(spacing: 10)
        row.addArrangedSubview(makeLabel(NSLocalizedString("Device", comment: ""), width: 128))

        let popup = NSPopUpButton()
        popup.identifier = NSUserInterfaceItemIdentifier("condition.device.\(groupIndex)")
        popup.target = self
        popup.action = #selector(deviceConditionChanged(_:))
        popup.addItems(withTitles: [
            NSLocalizedString("Any Device", comment: ""),
            NSLocalizedString("All Mice", comment: ""),
            NSLocalizedString("All Trackpads", comment: ""),
            NSLocalizedString("Current Device", comment: "")
        ])

        if matcher == nil {
            popup.selectItem(at: 0)
        } else if matcher?.category == [.mouse], matcher?.vendorID == nil, matcher?.productID == nil {
            popup.selectItem(at: 1)
        } else if matcher?.category == [.trackpad], matcher?.vendorID == nil, matcher?.productID == nil {
            popup.selectItem(at: 2)
        } else {
            popup.selectItem(at: 3)
        }

        row.addArrangedSubview(popup)
        let summary = makeLabel(RulePresenter.deviceSummary(matcher), color: .secondaryLabelColor)
        summary.lineBreakMode = .byTruncatingTail
        row.addArrangedSubview(summary)
        row.addArrangedSubview(makeFlexibleSpace())
        return row
    }

    private func makeTextConditionRow(title: String, value: String?, key: TextConditionKey, groupIndex: Int) -> NSView {
        let row = horizontalStack(spacing: 10)
        row.addArrangedSubview(makeLabel(title, width: 128))

        let field = NSTextField(string: value ?? "")
        field.identifier = NSUserInterfaceItemIdentifier("condition.\(key.rawValue).\(groupIndex)")
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        row.addArrangedSubview(field)

        if key.supportsCurrentValue {
            let useCurrent = NSButton(
                title: key.currentButtonTitle,
                target: self,
                action: #selector(useCurrentConditionValue(_:))
            )
            useCurrent.identifier = NSUserInterfaceItemIdentifier("condition.\(key.rawValue).\(groupIndex)")
            row.addArrangedSubview(useCurrent)
        }

        let clear = NSButton(
            title: NSLocalizedString("Clear", comment: ""),
            target: self,
            action: #selector(clearCondition(_:))
        )
        clear.identifier = NSUserInterfaceItemIdentifier("condition.\(key.rawValue).\(groupIndex)")
        row.addArrangedSubview(clear)
        row.addArrangedSubview(makeFlexibleSpace())
        return row
    }

    private func makeSettingsSection(for scheme: Scheme) -> NSView {
        let section = makeSection(title: NSLocalizedString("Settings in This Rule", comment: ""))
        var addedRows = 0

        if let pointer = scheme.$pointer {
            let pointerRows = makePointerRows(pointer)
            if !pointerRows.isEmpty {
                section.content.addArrangedSubview(makeSubsectionTitle(NSLocalizedString("Pointer", comment: "")))
                pointerRows.forEach { section.content.addArrangedSubview($0) }
                addedRows += pointerRows.count
            }
        }

        if let scrolling = scheme.$scrolling {
            let scrollingRows = makeScrollingRows(scrolling)
            if !scrollingRows.isEmpty {
                section.content.addArrangedSubview(makeSubsectionTitle(NSLocalizedString("Scrolling", comment: "")))
                scrollingRows.forEach { section.content.addArrangedSubview($0) }
                addedRows += scrollingRows.count
            }
        }

        if let buttons = scheme.$buttons {
            let buttonRows = makeButtonRows(buttons)
            if !buttonRows.isEmpty {
                section.content.addArrangedSubview(makeSubsectionTitle(NSLocalizedString("Buttons", comment: "")))
                buttonRows.forEach { section.content.addArrangedSubview($0) }
                addedRows += buttonRows.count
            }
        }

        if addedRows == 0 {
            section.content.addArrangedSubview(makeNoteBox(NSLocalizedString(
                "This rule does not set any values yet. Add a setting to make it affect matching devices and apps.",
                comment: ""
            )))
        }

        let addRow = horizontalStack(spacing: 8)
        let addSettingButton = NSPopUpButton(frame: .zero, pullsDown: true)
        addSettingButton.addItem(withTitle: NSLocalizedString("Add Setting…", comment: ""))
        for (title, key) in SettingKey.addableItems {
            let item = NSMenuItem(title: title, action: #selector(addSetting(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key.rawValue
            addSettingButton.menu?.addItem(item)
        }
        addRow.addArrangedSubview(addSettingButton)
        addRow.addArrangedSubview(makeFlexibleSpace())
        section.content.addArrangedSubview(addRow)

        return section.view
    }

    private func makePointerRows(_ pointer: Scheme.Pointer) -> [NSView] {
        var rows: [NSView] = []

        if let acceleration = pointer.acceleration {
            rows.append(makeUnsettableDecimalRow(
                title: NSLocalizedString("Pointer acceleration", comment: ""),
                value: acceleration,
                setting: .pointerAcceleration,
                range: 0 ... 20
            ))
        }

        if let speed = pointer.speed {
            rows.append(makeUnsettableDecimalRow(
                title: NSLocalizedString("Pointer speed", comment: ""),
                value: speed,
                setting: .pointerSpeed,
                range: 0 ... 1
            ))
        }

        if let disableAcceleration = pointer.disableAcceleration {
            rows.append(makeCheckboxSettingRow(
                title: NSLocalizedString("Disable pointer acceleration", comment: ""),
                state: disableAcceleration,
                setting: .pointerDisableAcceleration
            ))
        }

        if let redirectsToScroll = pointer.redirectsToScroll {
            rows.append(makeCheckboxSettingRow(
                title: NSLocalizedString("Convert pointer movement to scroll events", comment: ""),
                state: redirectsToScroll,
                setting: .pointerRedirectsToScroll
            ))
        }

        return rows
    }

    private func makeScrollingRows(_ scrolling: Scheme.Scrolling) -> [NSView] {
        var rows: [NSView] = []

        if let value = scrolling.$reverse?.vertical {
            rows.append(makeCheckboxSettingRow(
                title: NSLocalizedString("Reverse vertical scrolling", comment: ""),
                state: value,
                setting: .scrollingReverseVertical
            ))
        }
        if let value = scrolling.$reverse?.horizontal {
            rows.append(makeCheckboxSettingRow(
                title: NSLocalizedString("Reverse horizontal scrolling", comment: ""),
                state: value,
                setting: .scrollingReverseHorizontal
            ))
        }
        if let value = scrolling.$distance?.vertical {
            rows.append(makeReadOnlySettingRow(
                title: NSLocalizedString("Vertical scrolling distance", comment: ""),
                value: String(describing: value),
                setting: .scrollingDistanceVertical
            ))
        }
        if let value = scrolling.$distance?.horizontal {
            rows.append(makeReadOnlySettingRow(
                title: NSLocalizedString("Horizontal scrolling distance", comment: ""),
                value: String(describing: value),
                setting: .scrollingDistanceHorizontal
            ))
        }
        if let value = scrolling.$acceleration?.vertical {
            rows.append(makeDecimalTextRow(
                title: NSLocalizedString("Vertical scrolling acceleration", comment: ""),
                value: value,
                setting: .scrollingAccelerationVertical
            ))
        }
        if let value = scrolling.$acceleration?.horizontal {
            rows.append(makeDecimalTextRow(
                title: NSLocalizedString("Horizontal scrolling acceleration", comment: ""),
                value: value,
                setting: .scrollingAccelerationHorizontal
            ))
        }
        if let value = scrolling.$speed?.vertical {
            rows.append(makeDecimalTextRow(
                title: NSLocalizedString("Vertical scrolling speed", comment: ""),
                value: value,
                setting: .scrollingSpeedVertical
            ))
        }
        if let value = scrolling.$speed?.horizontal {
            rows.append(makeDecimalTextRow(
                title: NSLocalizedString("Horizontal scrolling speed", comment: ""),
                value: value,
                setting: .scrollingSpeedHorizontal
            ))
        }
        if scrolling.$smoothed != nil {
            rows.append(makeReadOnlySettingRow(
                title: NSLocalizedString("Smoothed scrolling", comment: ""),
                value: NSLocalizedString("Configured", comment: ""),
                setting: .scrollingSmoothed
            ))
        }
        if scrolling.$modifiers != nil {
            rows.append(makeReadOnlySettingRow(
                title: NSLocalizedString("Modifier keys", comment: ""),
                value: NSLocalizedString("Configured", comment: ""),
                setting: .scrollingModifiers
            ))
        }

        return rows
    }

    private func makeButtonRows(_ buttons: Scheme.Buttons) -> [NSView] {
        var rows: [NSView] = []

        if let universalBackForward = buttons.universalBackForward {
            rows.append(makeCheckboxSettingRow(
                title: NSLocalizedString("Universal back and forward", comment: ""),
                state: universalBackForward != .none,
                setting: .buttonsUniversalBackForward
            ))
        }

        if let switchPrimary = buttons.switchPrimaryButtonAndSecondaryButtons {
            rows.append(makeCheckboxSettingRow(
                title: NSLocalizedString("Switch primary and secondary buttons", comment: ""),
                state: switchPrimary,
                setting: .buttonsSwitchPrimary
            ))
        }

        if buttons.$clickDebouncing != nil {
            rows.append(makeReadOnlySettingRow(
                title: NSLocalizedString("Click debouncing", comment: ""),
                value: RulePresenter.clickDebouncingSummary(buttons.clickDebouncing),
                setting: .buttonsClickDebouncing
            ))
        }

        if let autoScroll = buttons.$autoScroll {
            rows.append(makeCheckboxSettingRow(
                title: NSLocalizedString("Auto scroll", comment: ""),
                state: autoScroll.enabled ?? false,
                setting: .buttonsAutoScrollEnabled
            ))
        }

        if let gesture = buttons.$gesture {
            rows.append(makeCheckboxSettingRow(
                title: NSLocalizedString("Gesture button", comment: ""),
                state: gesture.enabled ?? false,
                setting: .buttonsGestureEnabled
            ))
        }

        if let mappings = buttons.mappings {
            rows.append(makeReadOnlySettingRow(
                title: NSLocalizedString("Button mappings", comment: ""),
                value: String(format: NSLocalizedString("%d mapping(s)", comment: ""), mappings.count),
                setting: .buttonsMappings
            ))
        }

        return rows
    }

    private func makeCheckboxSettingRow(title: String, state: Bool, setting: SettingKey) -> NSView {
        let row = horizontalStack(spacing: 10)
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged(_:)))
        checkbox.state = state ? .on : .off
        checkbox.identifier = NSUserInterfaceItemIdentifier(setting.rawValue)
        row.addArrangedSubview(checkbox)
        row.addArrangedSubview(makeFlexibleSpace())
        row.addArrangedSubview(sourcePill(for: setting))
        row.addArrangedSubview(removeButton(for: setting))
        return row
    }

    private func makeUnsettableDecimalRow(
        title: String,
        value: Unsettable<Decimal>,
        setting: SettingKey,
        range: ClosedRange<Double>
    ) -> NSView {
        switch value {
        case let .value(decimal):
            let row = horizontalStack(spacing: 10)
            row.addArrangedSubview(makeLabel(title, width: 190))
            let slider = NSSlider(
                value: decimal.asTruncatedDouble,
                minValue: range.lowerBound,
                maxValue: range.upperBound,
                target: self,
                action: #selector(sliderChanged(_:))
            )
            slider.identifier = NSUserInterfaceItemIdentifier(setting.rawValue)
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            row.addArrangedSubview(slider)
            let field = NSTextField(string: RulePresenter.decimalString(decimal))
            field.identifier = NSUserInterfaceItemIdentifier(setting.rawValue)
            field.delegate = self
            field.target = self
            field.action = #selector(textFieldCommitted(_:))
            field.alignment = .right
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 76).isActive = true
            row.addArrangedSubview(field)
            row.addArrangedSubview(sourcePill(for: setting))
            row.addArrangedSubview(removeButton(for: setting))
            return row
        case .unset:
            return makeReadOnlySettingRow(
                title: title,
                value: NSLocalizedString("Unset", comment: ""),
                setting: setting
            )
        }
    }

    private func makeDecimalTextRow(title: String, value: Decimal, setting: SettingKey) -> NSView {
        let row = horizontalStack(spacing: 10)
        row.addArrangedSubview(makeLabel(title, width: 220))
        let field = NSTextField(string: RulePresenter.decimalString(value))
        field.identifier = NSUserInterfaceItemIdentifier(setting.rawValue)
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 76).isActive = true
        row.addArrangedSubview(field)
        row.addArrangedSubview(makeFlexibleSpace())
        row.addArrangedSubview(sourcePill(for: setting))
        row.addArrangedSubview(removeButton(for: setting))
        return row
    }

    private func makeReadOnlySettingRow(title: String, value: String, setting: SettingKey) -> NSView {
        let row = horizontalStack(spacing: 10)
        row.addArrangedSubview(makeLabel(title, width: 220))
        let valueLabel = makeLabel(value, weight: .medium)
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(makeFlexibleSpace())
        row.addArrangedSubview(sourcePill(for: setting))
        row.addArrangedSubview(removeButton(for: setting))
        return row
    }

    private func sourcePill(for setting: SettingKey) -> NSTextField {
        if let source = RuleTrace(configuration: configurationState.configuration).source(
            for: setting,
            in: RuleContext.current
        ) {
            return makePill(source, accent: source == NSLocalizedString("Set here", comment: ""))
        }
        return makePill(NSLocalizedString("Not active", comment: ""))
    }

    private func removeButton(for setting: SettingKey) -> NSButton {
        let button = NSButton(
            title: NSLocalizedString("Remove", comment: ""),
            target: self,
            action: #selector(removeSetting(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(setting.rawValue)
        return button
    }

    private func makeEffectiveValuesSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("Effective Values for Current Preview", comment: ""))
        let context = RuleContext.current
        section.content.addArrangedSubview(makeContextSummary(context))

        let trace = RuleTrace(configuration: configurationState.configuration)
        let rows: [(String, SettingKey)] = [
            (NSLocalizedString("Pointer acceleration", comment: ""), .pointerAcceleration),
            (NSLocalizedString("Pointer speed", comment: ""), .pointerSpeed),
            (NSLocalizedString("Reverse vertical scrolling", comment: ""), .scrollingReverseVertical),
            (NSLocalizedString("Reverse horizontal scrolling", comment: ""), .scrollingReverseHorizontal),
            (NSLocalizedString("Universal back and forward", comment: ""), .buttonsUniversalBackForward)
        ]

        for (title, key) in rows {
            let row = horizontalStack(spacing: 10)
            row.addArrangedSubview(makeLabel(title, width: 220))
            row.addArrangedSubview(makeLabel(trace.valueDescription(for: key, in: context), weight: .medium))
            row.addArrangedSubview(makeFlexibleSpace())
            row.addArrangedSubview(makePill(
                trace.source(for: key, in: context) ?? NSLocalizedString("Default", comment: ""),
                accent: trace.source(for: key, in: context) != nil
            ))
            section.content.addArrangedSubview(row)
        }

        return section.view
    }

    private func makeActiveChainSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("Active Rule Chain", comment: ""))
        let context = RuleContext.current
        let activeRules = RuleTrace(configuration: configurationState.configuration).activeRules(in: context)

        if activeRules.isEmpty {
            section.content.addArrangedSubview(makeNoteBox(NSLocalizedString(
                "No rules match the current preview context.",
                comment: ""
            )))
        } else {
            for activeRule in activeRules {
                let row = horizontalStack(spacing: 10)
                row.addArrangedSubview(makePill("#\(activeRule.index + 1)", accent: true))
                let text = verticalStack(spacing: 2)
                text.addArrangedSubview(makeLabel(
                    RulePresenter.title(for: activeRule.scheme, at: activeRule.index),
                    weight: .semibold
                ))
                text.addArrangedSubview(makeLabel(
                    RulePresenter.changesSummary(for: activeRule.scheme),
                    color: .secondaryLabelColor
                ))
                row.addArrangedSubview(text)
                row.addArrangedSubview(makeFlexibleSpace())
                section.content.addArrangedSubview(row)
            }
        }

        return section.view
    }

    private func makeContextSummary(_ context: RuleContext) -> NSView {
        let row = horizontalStack(spacing: 8)
        row.addArrangedSubview(makePill(context.deviceName ?? NSLocalizedString("No Device", comment: "")))
        row.addArrangedSubview(makePill(context.appName ?? NSLocalizedString("No App", comment: "")))
        row.addArrangedSubview(makePill(context.display ?? NSLocalizedString("No Display", comment: "")))
        row.addArrangedSubview(makeFlexibleSpace())
        return row
    }

    private func makeJSONSection(for scheme: Scheme) -> NSView {
        let section = makeSection(title: NSLocalizedString("Rule JSON", comment: ""))
        section.content.addArrangedSubview(makeNoteBox(NSLocalizedString(
            "Advanced fields remain editable here. Applying JSON replaces only the selected rule.",
            comment: ""
        )))

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        let textView = NSTextView()
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = RulePresenter.jsonString(for: scheme)
        scrollView.documentView = textView
        jsonTextView = textView
        section.content.addArrangedSubview(scrollView)

        let row = horizontalStack(spacing: 8)
        let apply = NSButton(
            title: NSLocalizedString("Apply JSON", comment: ""),
            target: self,
            action: #selector(applyJSON)
        )
        row.addArrangedSubview(apply)
        row.addArrangedSubview(makeFlexibleSpace())
        section.content.addArrangedSubview(row)
        return section.view
    }

    // MARK: Actions

    @objc private func addCondition(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? RuleConditionKind else {
            return
        }

        updateSelectedRule { scheme in
            var conditions = scheme.if ?? [.init()]
            if conditions.isEmpty {
                conditions = [.init()]
            }
            var condition = conditions[0]

            switch kind {
            case .device:
                if condition.device == nil {
                    condition.device = .init(category: [.mouse])
                }
            case .app:
                condition.app = condition.app ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            case .parentApp:
                condition.parentApp = condition.parentApp ?? RuleContext.current.parentApp ?? ""
            case .groupApp:
                condition.groupApp = condition.groupApp ?? RuleContext.current.groupApp ?? ""
            case .processName:
                condition.processName = condition.processName ?? RuleContext.current.processName ?? ""
            case .processPath:
                condition.processPath = condition.processPath ?? RuleContext.current.processPath ?? ""
            case .display:
                condition.display = condition.display ?? ScreenManager.shared.currentScreenName ?? ""
            }

            conditions[0] = condition
            scheme.if = conditions
        }
    }

    @objc private func addSetting(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let setting = SettingKey(rawValue: rawValue) else {
            return
        }

        updateSelectedRule { scheme in
            switch setting {
            case .pointerAcceleration:
                scheme.pointer.acceleration = .value(0.6875)
            case .pointerSpeed:
                scheme.pointer.speed = .value(0.5)
            case .pointerDisableAcceleration:
                scheme.pointer.disableAcceleration = true
            case .pointerRedirectsToScroll:
                scheme.pointer.redirectsToScroll = true
            case .scrollingReverseVertical:
                scheme.scrolling.reverse.vertical = true
            case .scrollingReverseHorizontal:
                scheme.scrolling.reverse.horizontal = true
            case .scrollingDistanceVertical:
                scheme.scrolling.distance.vertical = .auto
            case .scrollingDistanceHorizontal:
                scheme.scrolling.distance.horizontal = .auto
            case .scrollingAccelerationVertical:
                scheme.scrolling.acceleration.vertical = 1
            case .scrollingAccelerationHorizontal:
                scheme.scrolling.acceleration.horizontal = 1
            case .scrollingSpeedVertical:
                scheme.scrolling.speed.vertical = 0
            case .scrollingSpeedHorizontal:
                scheme.scrolling.speed.horizontal = 0
            case .scrollingSmoothed:
                scheme.scrolling.smoothed.vertical = .init(enabled: true, preset: .defaultPreset)
            case .scrollingModifiers:
                scheme.scrolling.modifiers.vertical = .init()
            case .buttonsUniversalBackForward:
                scheme.buttons.universalBackForward = .both
            case .buttonsSwitchPrimary:
                scheme.buttons.switchPrimaryButtonAndSecondaryButtons = true
            case .buttonsClickDebouncing:
                scheme.buttons.clickDebouncing.timeout = 50
            case .buttonsAutoScrollEnabled:
                scheme.buttons.autoScroll.enabled = true
            case .buttonsGestureEnabled:
                scheme.buttons.gesture.enabled = true
            case .buttonsMappings:
                var mapping = Scheme.Buttons.Mapping()
                mapping.button = .mouse(Int(CGMouseButton.center.rawValue))
                scheme.buttons.mappings = (scheme.buttons.mappings ?? []) + [mapping]
            }
        }
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        guard let setting = SettingKey(rawValue: sender.identifier?.rawValue ?? "") else {
            return
        }
        let value = sender.state == .on
        updateSelectedRule { scheme in
            switch setting {
            case .pointerDisableAcceleration:
                scheme.pointer.disableAcceleration = value
            case .pointerRedirectsToScroll:
                scheme.pointer.redirectsToScroll = value
                GlobalEventTap.shared.stop()
                GlobalEventTap.shared.start()
            case .scrollingReverseVertical:
                scheme.scrolling.reverse.vertical = value
            case .scrollingReverseHorizontal:
                scheme.scrolling.reverse.horizontal = value
            case .buttonsUniversalBackForward:
                scheme.buttons.universalBackForward = value ? .both : Scheme.Buttons.UniversalBackForward.none
            case .buttonsSwitchPrimary:
                scheme.buttons.switchPrimaryButtonAndSecondaryButtons = value
            case .buttonsAutoScrollEnabled:
                scheme.buttons.autoScroll.enabled = value
                GlobalEventTap.shared.stop()
                GlobalEventTap.shared.start()
            case .buttonsGestureEnabled:
                scheme.buttons.gesture.enabled = value
                GlobalEventTap.shared.stop()
                GlobalEventTap.shared.start()
            default:
                break
            }
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let setting = SettingKey(rawValue: sender.identifier?.rawValue ?? "") else {
            return
        }
        let value = Decimal(sender.doubleValue).rounded(4)
        updateSelectedRule { scheme in
            switch setting {
            case .pointerAcceleration:
                scheme.pointer.acceleration = .value(value)
            case .pointerSpeed:
                scheme.pointer.speed = .value(value)
            default:
                break
            }
        }
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        applyTextField(sender)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }
        applyTextField(field)
    }

    private func applyTextField(_ field: NSTextField) {
        guard let identifier = field.identifier?.rawValue else {
            return
        }

        if identifier.hasPrefix("condition.") {
            applyConditionTextField(field, identifier: identifier)
            return
        }

        guard let setting = SettingKey(rawValue: identifier) else {
            return
        }

        let decimal = Decimal(string: field.stringValue)
        updateSelectedRule { scheme in
            switch setting {
            case .pointerAcceleration:
                if let decimal {
                    scheme.pointer.acceleration = .value(decimal.rounded(4))
                }
            case .pointerSpeed:
                if let decimal {
                    scheme.pointer.speed = .value(decimal.rounded(4))
                }
            case .scrollingAccelerationVertical:
                if let decimal {
                    scheme.scrolling.acceleration.vertical = decimal.rounded(2)
                }
            case .scrollingAccelerationHorizontal:
                if let decimal {
                    scheme.scrolling.acceleration.horizontal = decimal.rounded(2)
                }
            case .scrollingSpeedVertical:
                if let decimal {
                    scheme.scrolling.speed.vertical = decimal.rounded(2)
                }
            case .scrollingSpeedHorizontal:
                if let decimal {
                    scheme.scrolling.speed.horizontal = decimal.rounded(2)
                }
            default:
                break
            }
        }
    }

    private func applyConditionTextField(_ field: NSTextField, identifier: String) {
        let parts = identifier.split(separator: ".")
        guard parts.count == 3,
              let key = TextConditionKey(rawValue: String(parts[1])),
              let groupIndex = Int(parts[2]) else {
            return
        }
        setConditionValue(field.stringValue, key: key, groupIndex: groupIndex)
    }

    @objc private func clearCondition(_ sender: NSButton) {
        guard let parsed = parseConditionControlIdentifier(sender.identifier?.rawValue) else {
            return
        }
        setConditionValue(nil, key: parsed.key, groupIndex: parsed.groupIndex)
    }

    @objc private func useCurrentConditionValue(_ sender: NSButton) {
        guard let parsed = parseConditionControlIdentifier(sender.identifier?.rawValue) else {
            return
        }

        let context = RuleContext.current
        let value: String?
        switch parsed.key {
        case .app:
            value = context.app
        case .parentApp:
            value = context.parentApp
        case .groupApp:
            value = context.groupApp
        case .processName:
            value = context.processName
        case .processPath:
            value = context.processPath
        case .display:
            value = context.display
        }

        setConditionValue(value ?? "", key: parsed.key, groupIndex: parsed.groupIndex)
    }

    @objc private func deviceConditionChanged(_ sender: NSPopUpButton) {
        guard let identifier = sender.identifier?.rawValue,
              let groupIndex = Int(identifier.split(separator: ".").last ?? "") else {
            return
        }

        updateSelectedRule { scheme in
            var conditions = scheme.if ?? [.init()]
            guard groupIndex < conditions.count else {
                return
            }

            switch sender.indexOfSelectedItem {
            case 0:
                conditions[groupIndex].device = nil
            case 1:
                conditions[groupIndex].device = .init(category: [.mouse])
            case 2:
                conditions[groupIndex].device = .init(category: [.trackpad])
            default:
                if let device = DeviceState.shared.currentDeviceRef?.value {
                    conditions[groupIndex].device = .init(of: device)
                }
            }

            scheme.if = normalizedConditions(conditions)
        }
    }

    @objc private func removeSetting(_ sender: NSButton) {
        guard let setting = SettingKey(rawValue: sender.identifier?.rawValue ?? "") else {
            return
        }

        updateSelectedRule { scheme in
            switch setting {
            case .pointerAcceleration:
                scheme.pointer.acceleration = nil
            case .pointerSpeed:
                scheme.pointer.speed = nil
            case .pointerDisableAcceleration:
                scheme.pointer.disableAcceleration = nil
            case .pointerRedirectsToScroll:
                scheme.pointer.redirectsToScroll = nil
            case .scrollingReverseVertical:
                scheme.scrolling.reverse.vertical = nil
            case .scrollingReverseHorizontal:
                scheme.scrolling.reverse.horizontal = nil
            case .scrollingDistanceVertical:
                scheme.scrolling.distance.vertical = nil
            case .scrollingDistanceHorizontal:
                scheme.scrolling.distance.horizontal = nil
            case .scrollingAccelerationVertical:
                scheme.scrolling.acceleration.vertical = nil
            case .scrollingAccelerationHorizontal:
                scheme.scrolling.acceleration.horizontal = nil
            case .scrollingSpeedVertical:
                scheme.scrolling.speed.vertical = nil
            case .scrollingSpeedHorizontal:
                scheme.scrolling.speed.horizontal = nil
            case .scrollingSmoothed:
                scheme.$scrolling?.smoothed = .init()
            case .scrollingModifiers:
                scheme.$scrolling?.modifiers = .init()
            case .buttonsUniversalBackForward:
                scheme.buttons.universalBackForward = nil
            case .buttonsSwitchPrimary:
                scheme.buttons.switchPrimaryButtonAndSecondaryButtons = nil
            case .buttonsClickDebouncing:
                scheme.$buttons?.clickDebouncing = .init()
            case .buttonsAutoScrollEnabled:
                scheme.$buttons?.autoScroll.enabled = nil
            case .buttonsGestureEnabled:
                scheme.$buttons?.gesture.enabled = nil
            case .buttonsMappings:
                scheme.buttons.mappings = nil
            }
        }
    }

    @objc private func applyJSON() {
        guard let json = jsonTextView?.string else {
            return
        }

        do {
            let data = Data(json.utf8)
            let scheme = try JSONDecoder().decode(Scheme.self, from: data)
            updateSelectedRule { target in
                target = scheme
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = NSLocalizedString("Invalid Rule JSON", comment: "")
            alert.runModal()
        }
    }

    private func setConditionValue(_ value: String?, key: TextConditionKey, groupIndex: Int) {
        updateSelectedRule { scheme in
            var conditions = scheme.if ?? [.init()]
            guard groupIndex < conditions.count else {
                return
            }

            let normalizedValue = value?.isEmpty == true ? nil : value
            switch key {
            case .app:
                conditions[groupIndex].app = normalizedValue
            case .parentApp:
                conditions[groupIndex].parentApp = normalizedValue
            case .groupApp:
                conditions[groupIndex].groupApp = normalizedValue
            case .processName:
                conditions[groupIndex].processName = normalizedValue
            case .processPath:
                conditions[groupIndex].processPath = normalizedValue
            case .display:
                conditions[groupIndex].display = normalizedValue
            }

            scheme.if = normalizedConditions(conditions)
        }
    }

    private func updateSelectedRule(_ update: (inout Scheme) -> Void) {
        guard let selectedRuleIndex,
              selectedRuleIndex >= 0,
              selectedRuleIndex < configurationState.configuration.schemes.count else {
            return
        }

        var configuration = configurationState.configuration
        update(&configuration.schemes[selectedRuleIndex])
        configurationState.configuration = configuration
    }

    private func parseConditionControlIdentifier(_ identifier: String?) -> (key: TextConditionKey, groupIndex: Int)? {
        guard let identifier else {
            return nil
        }
        let parts = identifier.split(separator: ".")
        guard parts.count == 3,
              let key = TextConditionKey(rawValue: String(parts[1])),
              let groupIndex = Int(parts[2]) else {
            return nil
        }
        return (key, groupIndex)
    }
}

// MARK: - General settings

final class GeneralSettingsViewController: NSViewController {
    private let updaterViewModel = UpdaterViewModel.shared
    private let exportQueue = DispatchQueue(label: "log-export")
    private var subscriptions = Set<AnyCancellable>()
    private let contentStack = verticalStack(spacing: 14)
    private var exportingLogs = false

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        buildView()
        bindUpdater()
        renderContent()

        preferredContentSize = NSSize(width: 540, height: 680)
    }

    private func buildView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        pin(scrollView, to: view)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        documentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    private func bindUpdater() {
        updaterViewModel
            .$canCheckForUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.renderContent() }
            .store(in: &subscriptions)

        updaterViewModel
            .$automaticallyChecksForUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.renderContent() }
            .store(in: &subscriptions)

        updaterViewModel
            .$updateCheckInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.renderContent() }
            .store(in: &subscriptions)
    }

    private func renderContent() {
        for arrangedSubview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        contentStack.addArrangedSubview(makeLabel(
            NSLocalizedString("General", comment: ""),
            size: 20,
            weight: .semibold
        ))
        contentStack.addArrangedSubview(makeAppearanceSection())
        contentStack.addArrangedSubview(makeStartupSection())
        contentStack.addArrangedSubview(makeBehaviorSection())
        contentStack.addArrangedSubview(makeConfigurationSection())
        contentStack.addArrangedSubview(makeUpdatesSection())
        contentStack.addArrangedSubview(makeLoggingSection())
        contentStack.addArrangedSubview(makeLinksSection())
        contentStack.addArrangedSubview(makeDoneRow())
    }

    private func makeAppearanceSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("App", comment: ""))
        section.content.addArrangedSubview(makeDefaultCheckbox(
            title: NSLocalizedString("Show in menu bar", comment: ""),
            key: .showInMenuBar
        ))
        if !Defaults[.showInMenuBar] {
            section.content.addArrangedSubview(makeNoteBox(String(
                format: NSLocalizedString("To show the settings, launch %@ again.", comment: ""),
                LinearMouse.appName
            )))
        }

        if Defaults[.showInMenuBar] {
            section.content.addArrangedSubview(makeMenuBarBatteryRow())
        }

        section.content.addArrangedSubview(makeDefaultCheckbox(
            title: NSLocalizedString("Show in Dock", comment: ""),
            key: .showInDock
        ))
        return section.view
    }

    private func makeStartupSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("Startup", comment: ""))
        let checkbox = NSButton(
            checkboxWithTitle: NSLocalizedString("Start at login", comment: ""),
            target: self,
            action: #selector(startAtLoginChanged(_:))
        )
        checkbox.state = LaunchAtLogin.isEnabled ? .on : .off
        section.content.addArrangedSubview(checkbox)
        return section.view
    }

    private func makeBehaviorSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("Behavior", comment: ""))
        section.content.addArrangedSubview(makeDefaultCheckbox(
            title: NSLocalizedString("Bypass events from other applications", comment: ""),
            key: .bypassEventsFromOtherApplications
        ))
        section.content.addArrangedSubview(makeNoteBox(String(
            format: NSLocalizedString(
                "If enabled, %@ will not modify events sent by other applications, such as Logi Options+.",
                comment: ""
            ),
            LinearMouse.appName
        )))
        return section.view
    }

    private func makeConfigurationSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("Configuration", comment: ""))
        let row = horizontalStack(spacing: 8)
        let reload = NSButton(
            title: NSLocalizedString("Reload Config", comment: ""),
            target: self,
            action: #selector(reloadConfig)
        )
        reload.isEnabled = !ConfigurationState.shared.loading
        let reveal = NSButton(
            title: NSLocalizedString("Reveal Config in Finder…", comment: ""),
            target: self,
            action: #selector(revealConfig)
        )
        row.addArrangedSubview(reload)
        row.addArrangedSubview(reveal)
        row.addArrangedSubview(makeFlexibleSpace())
        section.content.addArrangedSubview(row)
        return section.view
    }

    private func makeUpdatesSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("Updates", comment: ""))
        section.content.addArrangedSubview(makeLabel(
            String(format: NSLocalizedString("Version: %@", comment: ""), LinearMouse.appVersion),
            color: .secondaryLabelColor
        ))
        section.content.addArrangedSubview(makeUpdaterCheckbox(
            title: NSLocalizedString("Check for updates automatically", comment: ""),
            isOn: updaterViewModel.automaticallyChecksForUpdates,
            action: #selector(automaticUpdatesChanged(_:))
        ))

        if updaterViewModel.automaticallyChecksForUpdates {
            section.content.addArrangedSubview(makeUpdateIntervalRow())
        }

        section.content.addArrangedSubview(makeDefaultCheckbox(
            title: NSLocalizedString("Receive beta updates", comment: ""),
            key: .betaChannelOn
        ))
        if Defaults[.betaChannelOn] {
            section.content.addArrangedSubview(makeNoteBox(NSLocalizedString(
                "Thank you for participating in the beta test.",
                comment: ""
            )))
        }

        let row = horizontalStack(spacing: 8)
        let button = NSButton(
            title: NSLocalizedString("Check for Updates…", comment: ""),
            target: self,
            action: #selector(checkForUpdates)
        )
        button.isEnabled = updaterViewModel.canCheckForUpdates
        row.addArrangedSubview(button)
        row.addArrangedSubview(makeFlexibleSpace())
        section.content.addArrangedSubview(row)
        return section.view
    }

    private func makeLoggingSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("Logging", comment: ""))
        section.content.addArrangedSubview(makeDefaultCheckbox(
            title: NSLocalizedString("Enable verbose logging", comment: ""),
            key: .verbosedLoggingOn
        ))
        section.content.addArrangedSubview(makeNoteBox(String(
            format: NSLocalizedString(
                "Verbose logging records input events and may increase CPU usage while using %@. Exported logs include entries from the last 5 minutes.",
                comment: ""
            ),
            LinearMouse.appName
        )))

        let row = horizontalStack(spacing: 8)
        let button = NSButton(
            title: exportingLogs ? NSLocalizedString("Exporting…", comment: "") : NSLocalizedString(
                "Export Logs",
                comment: ""
            ),
            target: self,
            action: #selector(exportLogs)
        )
        button.isEnabled = !exportingLogs
        row.addArrangedSubview(button)
        row.addArrangedSubview(makeFlexibleSpace())
        section.content.addArrangedSubview(row)
        return section.view
    }

    private func makeLinksSection() -> NSView {
        let section = makeSection(title: NSLocalizedString("Links", comment: ""))
        let row = horizontalStack(spacing: 8)
        [
            (NSLocalizedString("Homepage", comment: ""), GeneralLink.homepage.rawValue),
            (NSLocalizedString("Bug Report", comment: ""), GeneralLink.bugReport.rawValue),
            (NSLocalizedString("Feature Request", comment: ""), GeneralLink.featureRequest.rawValue),
            (NSLocalizedString("Donate", comment: ""), GeneralLink.donate.rawValue)
        ].forEach { title, tag in
            let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
            button.bezelStyle = .inline
            button.tag = tag
            row.addArrangedSubview(button)
        }
        row.addArrangedSubview(makeFlexibleSpace())
        section.content.addArrangedSubview(row)
        return section.view
    }

    private func makeDoneRow() -> NSView {
        let doneRow = horizontalStack(spacing: 8)
        doneRow.addArrangedSubview(makeFlexibleSpace())
        let done = NSButton(title: NSLocalizedString("Done", comment: ""), target: self, action: #selector(done))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        doneRow.addArrangedSubview(done)
        return doneRow
    }

    private func makeMenuBarBatteryRow() -> NSView {
        let row = horizontalStack(spacing: 10)
        row.addArrangedSubview(makeLabel(NSLocalizedString("Show current battery", comment: ""), width: 180))
        let popup = NSPopUpButton()
        [
            (NSLocalizedString("Off", comment: ""), MenuBarBatteryDisplayMode.off),
            (String(format: NSLocalizedString("%@ or below", comment: ""), formattedPercent(5)), .below5),
            (String(format: NSLocalizedString("%@ or below", comment: ""), formattedPercent(10)), .below10),
            (String(format: NSLocalizedString("%@ or below", comment: ""), formattedPercent(15)), .below15),
            (String(format: NSLocalizedString("%@ or below", comment: ""), formattedPercent(20)), .below20),
            (NSLocalizedString("Always show", comment: ""), MenuBarBatteryDisplayMode.always)
        ].forEach { title, mode in
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = mode.rawValue
        }
        popup.selectItem(withTitle: batteryDisplayTitle(for: Defaults[.menuBarBatteryDisplayMode]))
        popup.target = self
        popup.action = #selector(menuBarBatteryChanged(_:))
        row.addArrangedSubview(popup)
        row.addArrangedSubview(makeFlexibleSpace())
        return row
    }

    private func makeUpdateIntervalRow() -> NSView {
        let row = horizontalStack(spacing: 10)
        row.addArrangedSubview(makeLabel(NSLocalizedString("Update check interval", comment: ""), width: 180))
        let popup = NSPopUpButton()
        [
            (NSLocalizedString("Daily", comment: ""), TimeInterval(86_400)),
            (NSLocalizedString("Weekly", comment: ""), TimeInterval(604_800)),
            (NSLocalizedString("Monthly", comment: ""), TimeInterval(2_629_800))
        ].forEach { title, interval in
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = interval
        }
        if let item = popup.itemArray
            .first(where: { ($0.representedObject as? TimeInterval) == updaterViewModel.updateCheckInterval }) {
            popup.select(item)
        }
        popup.target = self
        popup.action = #selector(updateIntervalChanged(_:))
        row.addArrangedSubview(popup)
        row.addArrangedSubview(makeFlexibleSpace())
        return row
    }

    private func makeDefaultCheckbox(title: String, key: GeneralCheckboxKey) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(defaultCheckboxChanged(_:)))
        checkbox.state = key.value ? .on : .off
        checkbox.tag = key.rawValue
        return checkbox
    }

    private func makeUpdaterCheckbox(title: String, isOn: Bool, action: Selector) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: action)
        checkbox.state = isOn ? .on : .off
        return checkbox
    }

    @objc private func defaultCheckboxChanged(_ sender: NSButton) {
        guard let key = GeneralCheckboxKey(rawValue: sender.tag) else {
            return
        }
        key.value = sender.state == .on
        if key == .showInMenuBar || key == .betaChannelOn {
            renderContent()
        }
    }

    @objc private func startAtLoginChanged(_ sender: NSButton) {
        LaunchAtLogin.isEnabled = sender.state == .on
    }

    @objc private func menuBarBatteryChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let mode = MenuBarBatteryDisplayMode(rawValue: rawValue) else {
            return
        }
        Defaults[.menuBarBatteryDisplayMode] = mode
    }

    @objc private func automaticUpdatesChanged(_ sender: NSButton) {
        updaterViewModel.automaticallyChecksForUpdates = sender.state == .on
    }

    @objc private func updateIntervalChanged(_ sender: NSPopUpButton) {
        guard let interval = sender.selectedItem?.representedObject as? TimeInterval else {
            return
        }
        updaterViewModel.updateCheckInterval = interval
    }

    @objc private func checkForUpdates() {
        updaterViewModel.checkForUpdates()
    }

    @objc private func openLink(_ sender: NSButton) {
        guard let link = GeneralLink(rawValue: sender.tag) else {
            return
        }
        NSWorkspace.shared.open(link.url)
    }

    @objc private func exportLogs() {
        exportingLogs = true
        renderContent()

        exportQueue.async { [weak self] in
            guard let self else {
                return
            }
            defer {
                DispatchQueue.main.async {
                    self.exportingLogs = false
                    self.renderContent()
                }
            }

            do {
                let logStore = try OSLogStore.local()
                let position = logStore.position(timeIntervalSinceEnd: -5 * 60)
                let predicate = NSPredicate(format: "subsystem == '\(LinearMouse.appBundleIdentifier)'")
                let entries = try logStore.getEntries(with: [], at: position, matching: predicate)
                let logs = entries
                    .compactMap { $0 as? OSLogEntryLog }
                    .filter { $0.subsystem == LinearMouse.appBundleIdentifier }
                    .suffix(100_000)
                    .map { "\($0.date)\t\(self.logLevel($0.level))\t\($0.category)\t\($0.composedMessage)\n" }
                    .joined()

                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let filePath = directory.appendingPathComponent("\(LinearMouse.appName).log")
                try logs.write(to: filePath, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([filePath.absoluteURL])
                }
            } catch {
                DispatchQueue.main.async {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    @objc private func reloadConfig() {
        ConfigurationState.shared.load()
    }

    @objc private func revealConfig() {
        ConfigurationState.shared.revealInFinder()
    }

    @objc private func done() {
        dismiss(nil)
    }

    private func logLevel(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined:
            return "undefined"
        case .debug:
            return "debug"
        case .info:
            return "info"
        case .notice:
            return "notice"
        case .error:
            return "error"
        case .fault:
            return "fault"
        default:
            return "level:\(level.rawValue)"
        }
    }

    private func batteryDisplayTitle(for mode: MenuBarBatteryDisplayMode) -> String {
        switch mode {
        case .off:
            return NSLocalizedString("Off", comment: "")
        case .below5:
            return String(format: NSLocalizedString("%@ or below", comment: ""), formattedPercent(5))
        case .below10:
            return String(format: NSLocalizedString("%@ or below", comment: ""), formattedPercent(10))
        case .below15:
            return String(format: NSLocalizedString("%@ or below", comment: ""), formattedPercent(15))
        case .below20:
            return String(format: NSLocalizedString("%@ or below", comment: ""), formattedPercent(20))
        case .always:
            return NSLocalizedString("Always show", comment: "")
        }
    }
}

private enum GeneralCheckboxKey: Int {
    case showInMenuBar
    case showInDock
    case betaChannelOn
    case bypassEventsFromOtherApplications
    case verbosedLoggingOn

    var value: Bool {
        get {
            switch self {
            case .showInMenuBar:
                return Defaults[.showInMenuBar]
            case .showInDock:
                return Defaults[.showInDock]
            case .betaChannelOn:
                return Defaults[.betaChannelOn]
            case .bypassEventsFromOtherApplications:
                return Defaults[.bypassEventsFromOtherApplications]
            case .verbosedLoggingOn:
                return Defaults[.verbosedLoggingOn]
            }
        }
        nonmutating set {
            switch self {
            case .showInMenuBar:
                Defaults[.showInMenuBar] = newValue
            case .showInDock:
                Defaults[.showInDock] = newValue
            case .betaChannelOn:
                Defaults[.betaChannelOn] = newValue
            case .bypassEventsFromOtherApplications:
                Defaults[.bypassEventsFromOtherApplications] = newValue
            case .verbosedLoggingOn:
                Defaults[.verbosedLoggingOn] = newValue
            }
        }
    }
}

private enum GeneralLink: Int {
    case homepage
    case bugReport
    case featureRequest
    case donate

    var url: URL {
        switch self {
        case .homepage:
            return URL(string: "https://linearmouse.app")!
        case .bugReport:
            return Self.withEnvironmentParametersAppended(for: URL(string: "https://go.linearmouse.app/bug-report")!)
        case .featureRequest:
            return Self
                .withEnvironmentParametersAppended(for: URL(string: "https://go.linearmouse.app/feature-request")!)
        case .donate:
            return URL(string: "https://go.linearmouse.app/donate")!
        }
    }

    private static func withEnvironmentParametersAppended(for url: URL) -> URL {
        var osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        if osVersion.hasPrefix("Version ") {
            osVersion = String(osVersion.dropFirst("Version ".count))
        }
        osVersion = "macOS \(osVersion)"

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "os", value: osVersion),
            URLQueryItem(name: "linearmouse", value: "v\(LinearMouse.appVersion)")
        ])
        components.queryItems = queryItems
        return components.url!
    }
}

// MARK: - Rule presenter and trace

private enum RulePresenter {
    static func title(for scheme: Scheme, at index: Int) -> String {
        if let name = scheme.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        guard let conditions = scheme.if, !conditions.isEmpty else {
            return NSLocalizedString("Global", comment: "")
        }

        if conditions.count > 1 {
            return String(format: NSLocalizedString("Rule %d", comment: ""), index + 1)
        }

        let condition = conditions[0]
        var parts: [String] = []

        if let device = condition.device {
            parts.append(deviceTitle(device))
        }

        if let app = condition.app {
            parts.append(appName(for: app) ?? app)
        }

        if let parentApp = condition.parentApp {
            parts.append(String(
                format: NSLocalizedString("Parent %@", comment: ""),
                appName(for: parentApp) ?? parentApp
            ))
        }

        if let groupApp = condition.groupApp {
            parts.append(String(format: NSLocalizedString("Group %@", comment: ""), appName(for: groupApp) ?? groupApp))
        }

        if let processName = condition.processName {
            parts.append(processName)
        }

        if let processPath = condition.processPath {
            parts.append(URL(fileURLWithPath: processPath).lastPathComponent)
        }

        if let display = condition.display {
            parts.append(display)
        }

        if parts.isEmpty {
            return String(format: NSLocalizedString("Rule %d", comment: ""), index + 1)
        }

        return parts.joined(separator: " + ")
    }

    static func summary(for scheme: Scheme) -> String {
        guard let conditions = scheme.if, !conditions.isEmpty else {
            return NSLocalizedString("Always", comment: "")
        }

        if conditions.count > 1 {
            return String(format: NSLocalizedString("Any of %d condition groups", comment: ""), conditions.count)
        }

        return conditionSummary(conditions[0])
    }

    static func conditionSummary(_ condition: Scheme.If) -> String {
        var parts: [String] = []

        if let device = condition.device {
            parts.append(String(format: NSLocalizedString("Device: %@", comment: ""), deviceSummary(device)))
        }
        if let app = condition.app {
            parts.append(String(format: NSLocalizedString("App: %@", comment: ""), appName(for: app) ?? app))
        }
        if let parentApp = condition.parentApp {
            parts.append(String(
                format: NSLocalizedString("Parent App: %@", comment: ""),
                appName(for: parentApp) ?? parentApp
            ))
        }
        if let groupApp = condition.groupApp {
            parts.append(String(
                format: NSLocalizedString("Group App: %@", comment: ""),
                appName(for: groupApp) ?? groupApp
            ))
        }
        if let processName = condition.processName {
            parts.append(String(format: NSLocalizedString("Process: %@", comment: ""), processName))
        }
        if let processPath = condition.processPath {
            parts.append(String(
                format: NSLocalizedString("Process Path: %@", comment: ""),
                URL(fileURLWithPath: processPath).lastPathComponent
            ))
        }
        if let display = condition.display {
            parts.append(String(format: NSLocalizedString("Display: %@", comment: ""), display))
        }

        return parts.isEmpty ? NSLocalizedString("Always", comment: "") : parts.joined(separator: ", ")
    }

    static func changesSummary(for scheme: Scheme) -> String {
        let changes = changes(for: scheme)
        return changes.isEmpty ? NSLocalizedString("No settings", comment: "") : changes.joined(separator: ", ")
    }

    static func changes(for scheme: Scheme) -> [String] {
        var changes: [String] = []
        if let pointer = scheme.$pointer {
            if pointer.acceleration != nil || pointer.speed != nil || pointer.disableAcceleration != nil || pointer
                .redirectsToScroll != nil {
                changes.append(NSLocalizedString("Pointer", comment: ""))
            }
        }
        if let scrolling = scheme.$scrolling {
            if scrolling.$reverse != nil || scrolling.$distance != nil || scrolling.$acceleration != nil || scrolling
                .$speed != nil || scrolling.$smoothed != nil || scrolling.$modifiers != nil {
                changes.append(NSLocalizedString("Scrolling", comment: ""))
            }
        }
        if let buttons = scheme.$buttons {
            if buttons.mappings != nil || buttons.universalBackForward != nil || buttons
                .switchPrimaryButtonAndSecondaryButtons != nil || buttons.$clickDebouncing != nil || buttons
                .$autoScroll != nil || buttons.$gesture != nil {
                changes.append(NSLocalizedString("Buttons", comment: ""))
            }
        }
        return changes
    }

    static func isActiveNow(_ scheme: Scheme) -> Bool {
        let context = RuleContext.current
        return scheme.isActive(
            withDevice: context.device,
            withApp: context.app,
            withParentApp: context.parentApp,
            withGroupApp: context.groupApp,
            withDisplay: context.display,
            withProcessName: context.processName,
            withProcessPath: context.processPath
        )
    }

    static func deviceTitle(_ matcher: DeviceMatcher) -> String {
        if matcher.vendorID == nil, matcher.productID == nil, matcher.category == [.mouse] {
            return NSLocalizedString("All Mice", comment: "")
        }
        if matcher.vendorID == nil, matcher.productID == nil, matcher.category == [.trackpad] {
            return NSLocalizedString("All Trackpads", comment: "")
        }
        return matcher.productName ?? NSLocalizedString("Specific Device", comment: "")
    }

    static func deviceSummary(_ matcher: DeviceMatcher?) -> String {
        guard let matcher else {
            return NSLocalizedString("Any Device", comment: "")
        }

        var parts: [String] = []
        if let category = matcher.category {
            parts.append(category.map(\.rawValue).joined(separator: ", "))
        }
        if let productName = matcher.productName {
            parts.append(productName)
        }
        if let vendorID = matcher.vendorID {
            parts.append(String(format: "Vendor 0x%04x", vendorID))
        }
        if let productID = matcher.productID {
            parts.append(String(format: "Product 0x%04x", productID))
        }
        if let serialNumber = matcher.serialNumber {
            parts.append(serialNumber)
        }
        return parts.isEmpty ? NSLocalizedString("Any Device", comment: "") : parts.joined(separator: ", ")
    }

    static func appName(for bundleIdentifier: String) -> String? {
        try? readInstalledApp(bundleIdentifier: bundleIdentifier)?.bundleName
    }

    static func decimalString(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }

    static func clickDebouncingSummary(_ clickDebouncing: Scheme.Buttons.ClickDebouncing) -> String {
        if let timeout = clickDebouncing.timeout, timeout > 0 {
            return String(format: NSLocalizedString("%d ms", comment: ""), timeout)
        }
        return NSLocalizedString("Configured", comment: "")
    }

    static func jsonString(for scheme: Scheme) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(scheme)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
}

private struct RuleTrace {
    let configuration: Configuration

    func activeRules(in context: RuleContext) -> [(index: Int, scheme: Scheme)] {
        configuration.schemes.enumerated().compactMap { index, scheme in
            guard scheme.isActive(
                withDevice: context.device,
                withApp: context.app,
                withParentApp: context.parentApp,
                withGroupApp: context.groupApp,
                withDisplay: context.display,
                withProcessName: context.processName,
                withProcessPath: context.processPath
            ) else {
                return nil
            }
            return (index: index, scheme: scheme)
        }
    }

    func source(for setting: SettingKey, in context: RuleContext) -> String? {
        var source: (Int, Scheme)?
        for activeRule in activeRules(in: context) where activeRule.scheme.explicitlySets(setting) {
            source = activeRule
        }
        guard let source else {
            return nil
        }
        return "#\(source.0 + 1) \(RulePresenter.title(for: source.1, at: source.0))"
    }

    func valueDescription(for setting: SettingKey, in context: RuleContext) -> String {
        let merged = configuration.matchScheme(
            withDevice: context.device,
            withApp: context.app,
            withParentApp: context.parentApp,
            withGroupApp: context.groupApp,
            withDisplay: context.display,
            withProcessName: context.processName,
            withProcessPath: context.processPath
        )

        switch setting {
        case .pointerAcceleration:
            return merged.pointer.acceleration.map(describeUnsettableDecimal) ?? NSLocalizedString(
                "System default",
                comment: ""
            )
        case .pointerSpeed:
            return merged.pointer.speed.map(describeUnsettableDecimal) ?? NSLocalizedString(
                "System default",
                comment: ""
            )
        case .scrollingReverseVertical:
            return merged.scrolling
                .reverse
                .vertical
                .map { $0 ? NSLocalizedString("On", comment: "") : NSLocalizedString(
                    "Off",
                    comment: ""
                )
                } ?? NSLocalizedString("Off", comment: "")
        case .scrollingReverseHorizontal:
            return merged.scrolling
                .reverse
                .horizontal
                .map { $0 ? NSLocalizedString("On", comment: "") : NSLocalizedString(
                    "Off",
                    comment: ""
                )
                } ?? NSLocalizedString("Off", comment: "")
        case .buttonsUniversalBackForward:
            return (merged.buttons.universalBackForward ?? Scheme.Buttons.UniversalBackForward.none) == Scheme.Buttons
                .UniversalBackForward.none ? NSLocalizedString(
                    "Off",
                    comment: ""
                ) : NSLocalizedString("On", comment: "")
        default:
            return NSLocalizedString("Configured", comment: "")
        }
    }

    private func describeUnsettableDecimal(_ value: Unsettable<Decimal>) -> String {
        switch value {
        case let .value(decimal):
            return RulePresenter.decimalString(decimal)
        case .unset:
            return NSLocalizedString("Unset", comment: "")
        }
    }
}

private struct RuleContext {
    let device: Device?
    let deviceName: String?
    let app: String?
    let appName: String?
    let parentApp: String?
    let groupApp: String?
    let processName: String?
    let processPath: String?
    let display: String?

    static var current: Self {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let app = pid?.bundleIdentifier
        let appName = app.flatMap(RulePresenter.appName(for:)) ?? NSWorkspace.shared.frontmostApplication?.localizedName
        let device = DeviceState.shared.currentDeviceRef?.value
        return Self(
            device: device,
            deviceName: device?.name,
            app: app,
            appName: appName,
            parentApp: pid?.parent?.bundleIdentifier,
            groupApp: pid?.group?.bundleIdentifier,
            processName: pid?.processName,
            processPath: pid?.processPath,
            display: ScreenManager.shared.currentScreenName
        )
    }
}

// MARK: - Keys and mutation helpers

private enum RuleConditionKind {
    case device
    case app
    case parentApp
    case groupApp
    case processName
    case processPath
    case display
}

private enum TextConditionKey: String {
    case app
    case parentApp
    case groupApp
    case processName
    case processPath
    case display

    var supportsCurrentValue: Bool {
        true
    }

    var currentButtonTitle: String {
        switch self {
        case .app, .parentApp, .groupApp:
            return NSLocalizedString("Use Current", comment: "")
        case .processName, .processPath:
            return NSLocalizedString("Use Frontmost", comment: "")
        case .display:
            return NSLocalizedString("Use Current", comment: "")
        }
    }
}

private enum SettingKey: String, CaseIterable {
    case pointerAcceleration
    case pointerSpeed
    case pointerDisableAcceleration
    case pointerRedirectsToScroll
    case scrollingReverseVertical
    case scrollingReverseHorizontal
    case scrollingDistanceVertical
    case scrollingDistanceHorizontal
    case scrollingAccelerationVertical
    case scrollingAccelerationHorizontal
    case scrollingSpeedVertical
    case scrollingSpeedHorizontal
    case scrollingSmoothed
    case scrollingModifiers
    case buttonsUniversalBackForward
    case buttonsSwitchPrimary
    case buttonsClickDebouncing
    case buttonsAutoScrollEnabled
    case buttonsGestureEnabled
    case buttonsMappings

    static var addableItems: [(String, Self)] {
        [
            (NSLocalizedString("Pointer Acceleration", comment: ""), .pointerAcceleration),
            (NSLocalizedString("Pointer Speed", comment: ""), .pointerSpeed),
            (NSLocalizedString("Disable Pointer Acceleration", comment: ""), .pointerDisableAcceleration),
            (NSLocalizedString("Convert Pointer Movement to Scroll", comment: ""), .pointerRedirectsToScroll),
            (NSLocalizedString("Reverse Vertical Scrolling", comment: ""), .scrollingReverseVertical),
            (NSLocalizedString("Reverse Horizontal Scrolling", comment: ""), .scrollingReverseHorizontal),
            (NSLocalizedString("Vertical Scrolling Acceleration", comment: ""), .scrollingAccelerationVertical),
            (NSLocalizedString("Horizontal Scrolling Acceleration", comment: ""), .scrollingAccelerationHorizontal),
            (NSLocalizedString("Universal Back and Forward", comment: ""), .buttonsUniversalBackForward),
            (NSLocalizedString("Switch Primary and Secondary Buttons", comment: ""), .buttonsSwitchPrimary),
            (NSLocalizedString("Auto Scroll", comment: ""), .buttonsAutoScrollEnabled),
            (NSLocalizedString("Gesture Button", comment: ""), .buttonsGestureEnabled),
            (NSLocalizedString("Click Debouncing", comment: ""), .buttonsClickDebouncing),
            (NSLocalizedString("Button Mapping", comment: ""), .buttonsMappings)
        ]
    }
}

private extension Scheme {
    func explicitlySets(_ setting: SettingKey) -> Bool {
        switch setting {
        case .pointerAcceleration:
            return $pointer?.acceleration != nil
        case .pointerSpeed:
            return $pointer?.speed != nil
        case .pointerDisableAcceleration:
            return $pointer?.disableAcceleration != nil
        case .pointerRedirectsToScroll:
            return $pointer?.redirectsToScroll != nil
        case .scrollingReverseVertical:
            return $scrolling?.$reverse?.vertical != nil
        case .scrollingReverseHorizontal:
            return $scrolling?.$reverse?.horizontal != nil
        case .scrollingDistanceVertical:
            return $scrolling?.$distance?.vertical != nil
        case .scrollingDistanceHorizontal:
            return $scrolling?.$distance?.horizontal != nil
        case .scrollingAccelerationVertical:
            return $scrolling?.$acceleration?.vertical != nil
        case .scrollingAccelerationHorizontal:
            return $scrolling?.$acceleration?.horizontal != nil
        case .scrollingSpeedVertical:
            return $scrolling?.$speed?.vertical != nil
        case .scrollingSpeedHorizontal:
            return $scrolling?.$speed?.horizontal != nil
        case .scrollingSmoothed:
            return $scrolling?.$smoothed != nil
        case .scrollingModifiers:
            return $scrolling?.$modifiers != nil
        case .buttonsUniversalBackForward:
            return $buttons?.universalBackForward != nil
        case .buttonsSwitchPrimary:
            return $buttons?.switchPrimaryButtonAndSecondaryButtons != nil
        case .buttonsClickDebouncing:
            return $buttons?.$clickDebouncing != nil
        case .buttonsAutoScrollEnabled:
            return $buttons?.$autoScroll?.enabled != nil
        case .buttonsGestureEnabled:
            return $buttons?.$gesture?.enabled != nil
        case .buttonsMappings:
            return $buttons?.mappings != nil
        }
    }
}

private extension Scheme.If {
    var isEmpty: Bool {
        device == nil &&
            app == nil &&
            parentApp == nil &&
            groupApp == nil &&
            processName == nil &&
            processPath == nil &&
            display == nil
    }

    var usesProcessCondition: Bool {
        parentApp != nil || groupApp != nil || processName != nil || processPath != nil
    }
}

private func normalizedConditions(_ conditions: [Scheme.If]) -> [Scheme.If]? {
    let nonEmpty = conditions.filter { !$0.isEmpty }
    return nonEmpty.isEmpty ? nil : nonEmpty
}

// MARK: - AppKit helpers

private struct SectionView {
    let view: NSView
    let content: NSStackView
}

private func makeSection(title: String) -> SectionView {
    let wrapper = verticalStack(spacing: 10)
    wrapper.addArrangedSubview(makeLabel(title, size: 15, weight: .semibold))

    let content = verticalStack(spacing: 10)
    content.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    content.wantsLayer = true
    content.layer?.cornerRadius = 8
    content.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

    wrapper.addArrangedSubview(content)
    return SectionView(view: wrapper, content: content)
}

private func makeSubsectionTitle(_ title: String) -> NSTextField {
    makeLabel(title.uppercased(), size: 11, color: .secondaryLabelColor, weight: .semibold)
}

private func makeNoteBox(_ text: String) -> NSView {
    let box = NSView()
    box.translatesAutoresizingMaskIntoConstraints = false
    box.wantsLayer = true
    box.layer?.cornerRadius = 7
    box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

    let label = makeLabel(text, color: .secondaryLabelColor)
    label.lineBreakMode = .byWordWrapping
    box.addSubview(label)
    pin(label, to: box, inset: NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11))
    return box
}

private func makeLabel(
    _ text: String,
    size: CGFloat = 13,
    color: NSColor = .labelColor,
    weight: NSFont.Weight = .regular,
    width: CGFloat? = nil
) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    if let width {
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
    }
    return label
}

private func makePill(_ text: String, accent: Bool = false) -> NSTextField {
    let label = makeLabel(text, size: 11, color: accent ? .controlAccentColor : .secondaryLabelColor, weight: .medium)
    label.alignment = .center
    label.wantsLayer = true
    label.layer?.cornerRadius = 5
    label.layer?
        .backgroundColor = (accent ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor
            .controlBackgroundColor).cgColor
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
    label.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
    return label
}

private func makeStatusDot() -> NSView {
    let dot = NSView()
    dot.translatesAutoresizingMaskIntoConstraints = false
    dot.wantsLayer = true
    dot.layer?.cornerRadius = 4
    dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    NSLayoutConstraint.activate([
        dot.widthAnchor.constraint(equalToConstant: 8),
        dot.heightAnchor.constraint(equalToConstant: 8)
    ])
    return dot
}

private func verticalStack(spacing: CGFloat) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

private func horizontalStack(spacing: CGFloat) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

private func makeFlexibleSpace() -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
}

private func pin(
    _ child: NSView,
    to parent: NSView,
    inset: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
) {
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset.top),
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset.left),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset.right),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset.bottom)
    ])
}
