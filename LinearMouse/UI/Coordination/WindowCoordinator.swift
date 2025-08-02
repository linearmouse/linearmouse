// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Combine

protocol WindowCoordinatorDelegate: AnyObject {
    func windowCoordinatorDidRequestClose(_ coordinator: WindowCoordinator)
}

class WindowCoordinator: NSObject {
    weak var delegate: WindowCoordinatorDelegate?

    private(set) var window: NSWindow?
    private var splitViewController: NSSplitViewController?
    private var sidebarViewController: SidebarViewController?
    private var contentViewController: ContentViewController?
    private var cancellables = Set<AnyCancellable>()

    private let navigationProvider: NavigationProvider
    private let contentFactory: ViewProvider

    init(
        navigationProvider: NavigationProvider = DefaultNavigationProvider(),
        contentFactory: ViewProvider = ContentViewFactory.shared
    ) {
        self.navigationProvider = navigationProvider
        self.contentFactory = contentFactory
        super.init()
    }

    deinit {
        cleanup()
    }

    func createWindow() -> NSWindow {
        if let existingWindow = window {
            return existingWindow
        }

        let newWindow = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 850, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configureWindow(newWindow)
        setupSplitView(for: newWindow)
        setupObservers()

        newWindow.center()
        window = newWindow

        return newWindow
    }

    private func configureWindow(_ window: NSWindow) {
        window.delegate = self
        window.title = LinearMouse.appName
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        if #available(macOS 15, *) {
            window.toolbar = NSToolbar()
            window.toolbar?.displayMode = .iconOnly
            window.toolbar?.allowsDisplayModeCustomization = false
        }
    }

    private func setupSplitView(for window: NSWindow) {
        splitViewController = NSSplitViewController()
        splitViewController?.splitView.frame = window.contentView!.bounds

        // Create sidebar
        sidebarViewController = SidebarViewController(navigationProvider: navigationProvider)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController!)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 200
        sidebarItem.canCollapse = false
        splitViewController?.addSplitViewItem(sidebarItem)

        // Create content view
        contentViewController = ContentViewController(contentFactory: contentFactory)
        let contentItem = NSSplitViewItem(contentListWithViewController: contentViewController!)
        contentItem.minimumThickness = 400

        if #available(macOS 26.0, *) {
            contentItem.automaticallyAdjustsSafeAreaInsets = true
        }

        splitViewController?.addSplitViewItem(contentItem)
        window.contentViewController = splitViewController
    }

    private func setupObservers() {
        SettingsState.shared
            .$navigation
            .sink { [weak self] navigation in
                self?.contentViewController?.updateContent(for: navigation)
            }
            .store(in: &cancellables)
    }

    private func cleanup() {
        cancellables.removeAll()

        // Clear the content view first to ensure proper cleanup
        window?.contentViewController = nil

        splitViewController = nil
        sidebarViewController = nil
        contentViewController = nil
        window = nil
    }
}

// MARK: - NSWindowDelegate

extension WindowCoordinator: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        cleanup()
        delegate?.windowCoordinatorDidRequestClose(self)
    }
}
