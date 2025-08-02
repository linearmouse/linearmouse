// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Combine
import SnapKit

class SidebarViewController: NSViewController {
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    private var cancellables = Set<AnyCancellable>()

    private let navigationProvider: NavigationProvider
    private var navigationItems: [NavigationItem] {
        navigationProvider.items
    }

    init(navigationProvider: NavigationProvider = DefaultNavigationProvider()) {
        self.navigationProvider = navigationProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        navigationProvider = DefaultNavigationProvider()
        super.init(coder: coder)
    }

    override func loadView() {
        view = NSView()

        setupOutlineView()
        setupLayout()
        setupObservers()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set initial selection
        if let currentNavigation = SettingsState.shared.navigation,
           let index = navigationItems.firstIndex(where: {
               ($0 as? SettingsNavigationItem)?.navigation == currentNavigation
           }) {
            outlineView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    private func setupOutlineView() {
        // Create outline view with native sidebar style
        outlineView = NSOutlineView()
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = nil

        outlineView.focusRingType = .none
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        outlineView.allowsEmptySelection = false
        outlineView.allowsMultipleSelection = false
        outlineView.usesAutomaticRowHeights = true
        outlineView.backgroundColor = .clear

        // Add column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.title = ""
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        // Create scroll view
        scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        view.addSubview(scrollView)
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view)
        }
    }

    private func setupObservers() {
        SettingsState.shared
            .$navigation
            .sink { [weak self] navigation in
                self?.updateSelection(for: navigation)
            }
            .store(in: &cancellables)
    }

    private func updateSelection(for navigation: SettingsState.Navigation?) {
        guard let navigation,
              let index = navigationItems.firstIndex(where: {
                  ($0 as? SettingsNavigationItem)?.navigation == navigation
              }) else {
            return
        }

        let indexSet = IndexSet(integer: index)
        if outlineView.selectedRowIndexes != indexSet {
            outlineView.selectRowIndexes(indexSet, byExtendingSelection: false)
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarViewController: NSOutlineViewDataSource {
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        item == nil ? navigationItems.count : 0
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem _: Any?) -> Any {
        navigationItems[index]
    }

    func outlineView(_: NSOutlineView, isItemExpandable _: Any) -> Bool {
        false
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarViewController: NSOutlineViewDelegate {
    func outlineView(_: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
        guard let navigationItem = item as? NavigationItem else {
            return nil
        }

        let cellView = SidebarCellView()
        cellView.configure(with: navigationItem)
        return cellView
    }

    func outlineView(_: NSOutlineView, shouldSelectItem _: Any) -> Bool {
        true
    }

    func outlineViewSelectionDidChange(_: Notification) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0, selectedRow < navigationItems.count else {
            return
        }

        let item = navigationItems[selectedRow]
        if let settingsItem = item as? SettingsNavigationItem {
            SettingsState.shared.navigation = settingsItem.navigation
        }
    }
}

// MARK: - Supporting Types

// SidebarNavigationItem moved to NavigationProtocols.swift

class SidebarCellView: NSTableCellView {
    private var stackView: NSStackView!
    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        stackView = NSStackView()
        stackView.spacing = 8

        // Icon
        iconImageView = NSImageView()
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.contentTintColor = .controlAccentColor
        iconImageView.snp.makeConstraints { make in
            make.width.equalTo(20)
        }
        stackView.addArrangedSubview(iconImageView)

        // Title
        titleLabel = NSTextField(labelWithString: "")
        stackView.addArrangedSubview(titleLabel)

        addSubview(stackView)

        stackView.snp.makeConstraints { make in
            make.edges.equalTo(self).inset(NSEdgeInsets(top: 6, left: 4, bottom: 6, right: 8))
        }
    }

    func configure(with item: NavigationItem) {
        if let settingsItem = item as? SettingsNavigationItem {
            let imageName = mapToCustomImageName(settingsItem.navigation)
            iconImageView.image = NSImage(named: imageName)
        }

        titleLabel.stringValue = item.title
    }

    private func mapToCustomImageName(_ navigation: SettingsState.Navigation) -> String {
        switch navigation {
        case .scrolling: return "Scrolling"
        case .pointer: return "Pointer"
        case .buttons: return "Buttons"
        case .general: return "General"
        }
    }
}
