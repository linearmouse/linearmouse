// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Combine

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

        view.addSubview(scrollView)
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        // Icon
        iconImageView = NSImageView()
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        // Title
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Layout with native sidebar spacing
        let leadingPadding: CGFloat = 12
        let iconSpacing: CGFloat = 8
        let iconSize: CGFloat = 16

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: iconSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }

    func configure(with item: NavigationItem) {
        // Try system symbol first, fall back to custom image
        if #available(macOS 11.0, *),
           let systemImage = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: item.title) {
            iconImageView.image = systemImage
        } else {
            // Fall back to custom images
            if let settingsItem = item as? SettingsNavigationItem {
                let imageName = mapToCustomImageName(settingsItem.navigation)
                iconImageView.image = NSImage(named: imageName)
            }
        }

        titleLabel.stringValue = item.title

        // Use native label colors
        if #available(macOS 14.0, *) {
            titleLabel.textColor = .labelColor
        }
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
