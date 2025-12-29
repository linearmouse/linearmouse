// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Cocoa
import Combine
import Defaults
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var released = true
    private var splitViewController: SettingsSplitViewController?
    private var showInDockTask: Task<Void, Never>?

    private func initWindowIfNeeded() {
        guard released else {
            return
        }

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.delegate = self
        window.title = LinearMouse.appName
        window.setFrameAutosaveName("SettingsWindow")
        window.minSize = NSSize(width: 700, height: 500)
        window.titlebarAppearsTransparent = true

        // Setup split view controller
        let splitVC = SettingsSplitViewController()
        splitViewController = splitVC
        window.contentViewController = splitVC

        // Setup toolbar with sidebar tracking separator
        let toolbar = SettingsToolbar(splitViewController: splitVC)
        window.toolbar = toolbar

        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }

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
        splitViewController = nil
        released = true
    }
}

// MARK: - SettingsSplitViewController

class SettingsSplitViewController: NSSplitViewController {
    private let sidebarViewController = SettingsSidebarViewController()
    private let detailViewController = SettingsDetailViewController()

    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Sidebar
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 250
        if #available(macOS 11.0, *) {
            sidebarItem.allowsFullHeightLayout = true
        }
        addSplitViewItem(sidebarItem)

        // Detail
        let detailItem = NSSplitViewItem(viewController: detailViewController)
        detailItem.minimumThickness = 450
        addSplitViewItem(detailItem)

        // Observe navigation changes
        SettingsState.shared
            .$navigation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] navigation in
                self?.detailViewController.updateContent(for: navigation)
            }
            .store(in: &cancellables)
    }

    var currentNavigation: SettingsState.Navigation? {
        SettingsState.shared.navigation
    }
}

// MARK: - SettingsSidebarViewController

class SettingsSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    private let items = SettingsState.Navigation.allCases

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupTableView()
        setupConstraints()

        // Select initial row
        if let navigation = SettingsState.shared.navigation,
           let index = items.firstIndex(of: navigation) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = 32
        if #available(macOS 11.0, *) {
            tableView.style = .sourceList
        }
        tableView.selectionHighlightStyle = .sourceList

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.isEditable = false
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        view.addSubview(scrollView)
    }

    private func setupConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in _: NSTableView) -> Int {
        items.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]

        let cellIdentifier = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell: NSTableCellView

        if let existingCell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView {
            cell = existingCell
        } else {
            cell = NSTableCellView()
            cell.identifier = cellIdentifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.imageView?.image = NSImage(named: item.imageName)
        cell.textField?.stringValue = NSLocalizedString(item.rawValue.capitalized, comment: "")

        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else {
            return
        }
        SettingsState.shared.navigation = items[selectedRow]
    }
}

// MARK: - SettingsDetailViewController

class SettingsDetailViewController: NSViewController {
    private var hostingController: NSHostingController<AnyView>?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateContent(for: SettingsState.shared.navigation)
    }

    func updateContent(for navigation: SettingsState.Navigation?) {
        // Remove old hosting controller
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        // Create new content
        let content: AnyView
        switch navigation {
        case .pointer:
            content = AnyView(PointerSettings())
        case .scrolling:
            content = AnyView(ScrollingSettings())
        case .buttons:
            content = AnyView(ButtonsSettings())
        case .general:
            content = AnyView(GeneralSettings())
        case .none:
            content = AnyView(
                Text("Select an item from the sidebar")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        let hosting = NSHostingController(rootView: content)
        addChild(hosting)
        view.addSubview(hosting.view)

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController = hosting
    }
}

// MARK: - SettingsToolbar

class SettingsToolbar: NSToolbar, NSToolbarDelegate {
    private weak var splitViewController: SettingsSplitViewController?
    private var cancellables = Set<AnyCancellable>()

    private static let deviceItemIdentifier = NSToolbarItem.Identifier("device")
    private static let appItemIdentifier = NSToolbarItem.Identifier("app")
    private static let displayItemIdentifier = NSToolbarItem.Identifier("display")
    private static let flexibleSpaceIdentifier = NSToolbarItem.Identifier.flexibleSpace

    init(splitViewController: SettingsSplitViewController) {
        self.splitViewController = splitViewController
        super.init(identifier: "SettingsToolbar")

        delegate = self
        displayMode = .iconOnly
        allowsUserCustomization = false
        if #available(macOS 15.0, *) {
            allowsDisplayModeCustomization = false
        }

        // Observe navigation changes to show/hide toolbar items
        SettingsState.shared
            .$navigation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateVisibleItems()
            }
            .store(in: &cancellables)
    }

    private var shouldShowSchemeIndicators: Bool {
        guard let navigation = splitViewController?.currentNavigation else {
            return false
        }
        return navigation != .general
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.deviceItemIdentifier:
            return createIndicatorItem(identifier: itemIdentifier, indicator: DeviceIndicatorButton())
        case Self.appItemIdentifier:
            return createIndicatorItem(identifier: itemIdentifier, indicator: AppIndicatorButton())
        case Self.displayItemIdentifier:
            return createIndicatorItem(identifier: itemIdentifier, indicator: DisplayIndicatorButton())
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = []
        if #available(macOS 11.0, *) {
            identifiers.append(.sidebarTrackingSeparator)
        }
        identifiers.append(contentsOf: [
            Self.flexibleSpaceIdentifier,
            Self.deviceItemIdentifier,
            Self.appItemIdentifier,
            Self.displayItemIdentifier
        ])
        return identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    private func createIndicatorItem(identifier: NSToolbarItem.Identifier, indicator: NSButton) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = indicator
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.deviceItemIdentifier, Self.appItemIdentifier, Self.displayItemIdentifier:
            item.view?.isHidden = !shouldShowSchemeIndicators
            return shouldShowSchemeIndicators
        default:
            return true
        }
    }
}

// MARK: - Indicator Buttons

class DeviceIndicatorButton: NSButton {
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(frame: .zero)
        setupButton()
        bindState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupButton() {
        bezelStyle = .toolbar
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(showPicker)
        translatesAutoresizingMaskIntoConstraints = false
    }

    private func bindState() {
        DeviceIndicatorState.shared
            .$activeDeviceName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.title = name ?? NSLocalizedString("Unknown", comment: "")
            }
            .store(in: &cancellables)
    }

    @objc private func showPicker() {
        guard let contentVC = window?.contentViewController else {
            return
        }
        let sheetController = SheetController(content: DevicePickerSheetContent.self)
        contentVC.presentAsSheet(sheetController)
    }
}

class AppIndicatorButton: NSButton {
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(frame: .zero)
        setupButton()
        bindState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupButton() {
        bezelStyle = .toolbar
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(showPicker)
        translatesAutoresizingMaskIntoConstraints = false
    }

    private func bindState() {
        SchemeState.shared
            .$currentApp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let name = SchemeState.shared.currentAppName
                self?.title = name ?? NSLocalizedString("All Apps", comment: "")
            }
            .store(in: &cancellables)
    }

    @objc private func showPicker() {
        guard let contentVC = window?.contentViewController else {
            return
        }
        let sheetController = SheetController(content: AppPickerSheetContent.self)
        contentVC.presentAsSheet(sheetController)
    }
}

class DisplayIndicatorButton: NSButton {
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(frame: .zero)
        setupButton()
        bindState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupButton() {
        bezelStyle = .toolbar
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(showPicker)
        translatesAutoresizingMaskIntoConstraints = false
    }

    private func bindState() {
        SchemeState.shared
            .$currentDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.title = name ?? NSLocalizedString("All Displays", comment: "")
            }
            .store(in: &cancellables)
    }

    @objc private func showPicker() {
        guard let contentVC = window?.contentViewController else {
            return
        }
        let sheetController = SheetController(content: DisplayPickerSheetContent.self)
        contentVC.presentAsSheet(sheetController)
    }
}

// MARK: - Sheet Controller

private protocol SheetContentView: View {
    init(isPresented: Binding<Bool>)
}

extension DevicePickerSheetContent: SheetContentView {}
extension AppPickerSheetContent: SheetContentView {}
extension DisplayPickerSheetContent: SheetContentView {}

private class SheetController<Content: SheetContentView>: NSViewController {
    private var hostingController: NSHostingController<Content>?
    private var isPresented = true {
        didSet {
            if !isPresented {
                dismiss(nil)
            }
        }
    }

    private let contentType: Content.Type

    init(content: Content.Type) {
        contentType = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let binding = Binding<Bool>(
            get: { [weak self] in self?.isPresented ?? false },
            set: { [weak self] in self?.isPresented = $0 }
        )

        let content = contentType.init(isPresented: binding)
        let hosting = NSHostingController(rootView: content)

        addChild(hosting)
        view.addSubview(hosting.view)

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController = hosting

        // Set preferred content size based on hosting view's fitting size
        DispatchQueue.main.async { [weak self] in
            guard let self, let hosting = self.hostingController else {
                return
            }
            let fittingSize = hosting.view.fittingSize
            self.preferredContentSize = fittingSize
        }
    }

    // Handle ESC key to dismiss
    @objc func cancel(_: Any?) {
        isPresented = false
    }
}

// MARK: - Sheet Content Views

private struct DevicePickerSheetContent: View {
    @Binding var isPresented: Bool

    var body: some View {
        DevicePickerSheet(isPresented: $isPresented)
            .frame(width: 400)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AppPickerSheetContent: View {
    @Binding var isPresented: Bool

    var body: some View {
        AppPickerSheet(isPresented: $isPresented)
            .frame(width: 400)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DisplayPickerSheetContent: View {
    @Binding var isPresented: Bool

    var body: some View {
        DisplayPickerSheet(isPresented: $isPresented)
            .frame(width: 400)
            .fixedSize(horizontal: false, vertical: true)
    }
}
