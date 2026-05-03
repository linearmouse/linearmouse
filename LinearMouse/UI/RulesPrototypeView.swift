// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Foundation
import KeyKit
import ObservationToken

final class RulesPrototypeHostingController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource,
    NSTableViewDelegate {
    private let configurationState = ConfigurationState.shared
    private let deviceState = DeviceState.shared
    private let settingsState = SettingsState.shared
    private let undoTarget = RulesPrototypeUndoTarget()

    private var subscriptions = Set<AnyCancellable>()
    private var selectedRuleIndex = 0
    private var selectedSectionID = RulesPrototypeSettingsSection.pointerMovement.id
    private var recordingObservationToken: ObservationToken?
    private var recordedButtonCancellable: AnyCancellable?
    private var recordingTarget: RulesPrototypeRecordingTarget?
    private weak var recordingButton: NSButton?
    private var keyRecordingObservationToken: ObservationToken?
    private var keyRecordingIndex: Int?
    private weak var keyRecordingButton: NSButton?
    private var keyRecordingModifiers: CGEventFlags = []
    private var rulePopover: NSPopover?
    private var appliesToPopover: NSPopover?

    private let sidebarTableView = NSTableView()
    private let mainScrollView = NSScrollView()
    private let topScrollEdgeView = RulesPrototypeScrollEdgeEffectView(edge: .top)
    private let bottomScrollEdgeView = RulesPrototypeScrollEdgeEffectView(edge: .bottom)
    private let settingsContent = NSStackView()
    private let rulePickerButton = RulesPrototypeRulePickerControl()
    private let titleField = NSTextField()
    private var sidebarRows = [RulesPrototypeSidebarListRow]()
    private var isUpdatingSidebarSelection = false
    private var scrollEdgeObservers = [NSObjectProtocol]()
    private var renderedSectionID: String?

    private var schemes: [Scheme] {
        configurationState.configuration.schemes
    }

    private var selectedScheme: Scheme? {
        guard schemes.indices.contains(selectedRuleIndex) else {
            return nil
        }
        return schemes[selectedRuleIndex]
    }

    private var currentDevice: Device? {
        deviceState.currentDeviceRef?.value
    }

    override func loadView() {
        view = RulesPrototypeCanvasView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildView()
        bindState()
        normalizeSelection()
        ensureVisibleDefaultRule()
        renderAll()
    }

    deinit {
        stopRecording()
        stopKeyRecording(resetButton: false)
        for observer in scrollEdgeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func buildView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = RulesPrototypePalette.windowBackground.cgColor

        let splitController = NSSplitViewController()
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        addChild(splitController)
        splitController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitController.view)
        rpPin(splitController.view, to: view)

        let sidebar = RulesPrototypeCanvasView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = RulesPrototypePalette.sidebarBackground.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 258).isActive = true
        let sidebarController = NSViewController()
        sidebarController.view = sidebar
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 258
        sidebarItem.maximumThickness = 258
        if #available(macOS 11.0, *) {
            sidebarItem.allowsFullHeightLayout = true
        }
        splitController.addSplitViewItem(sidebarItem)

        let rulesBox = rpVerticalStack(spacing: 7)
        rulesBox.translatesAutoresizingMaskIntoConstraints = false
        rulesBox.widthAnchor.constraint(equalToConstant: 230).isActive = true
        sidebar.addSubview(rulesBox)

        let rulesHeading = rpLabel(
            NSLocalizedString("Rules", comment: ""),
            size: 12,
            color: .secondaryLabelColor,
            weight: .semibold
        )
        rulesHeading.widthAnchor.constraint(equalToConstant: 230).isActive = true
        rulesBox.addArrangedSubview(rulesHeading)

        rulePickerButton.onClick = { [weak self] in
            self?.showRulePopover(self?.rulePickerButton)
        }
        rulePickerButton.translatesAutoresizingMaskIntoConstraints = false
        rulePickerButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
        rulePickerButton.widthAnchor.constraint(equalToConstant: 230).isActive = true
        rulesBox.addArrangedSubview(rulePickerButton)

        let sidebarListScrollView = NSScrollView()
        sidebarListScrollView.drawsBackground = false
        sidebarListScrollView.hasVerticalScroller = false
        sidebarListScrollView.hasHorizontalScroller = false
        sidebarListScrollView.autohidesScrollers = true
        sidebarListScrollView.contentInsets = NSEdgeInsetsZero
        sidebarListScrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarListScrollView)

        configureSidebarTableView()
        sidebarListScrollView.documentView = sidebarTableView

        let rulesTopAnchor: NSLayoutYAxisAnchor
        let rulesTopInset: CGFloat
        if #available(macOS 11.0, *) {
            rulesTopAnchor = sidebar.safeAreaLayoutGuide.topAnchor
            rulesTopInset = 8
        } else {
            rulesTopAnchor = sidebar.topAnchor
            rulesTopInset = 54
        }

        NSLayoutConstraint.activate([
            rulesBox.topAnchor.constraint(equalTo: rulesTopAnchor, constant: rulesTopInset),
            rulesBox.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            rulesBox.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            sidebarListScrollView.topAnchor.constraint(equalTo: rulesBox.bottomAnchor, constant: 18),
            sidebarListScrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            sidebarListScrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            sidebarListScrollView.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12)
        ])

        let detailContainer = RulesPrototypeCanvasView()
        detailContainer.wantsLayer = true
        detailContainer.layer?.backgroundColor = RulesPrototypePalette.windowBackground.cgColor
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        let detailController = NSViewController()
        detailController.view = detailContainer
        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 640
        splitController.addSplitViewItem(detailItem)

        mainScrollView.drawsBackground = false
        mainScrollView.hasVerticalScroller = true
        mainScrollView.hasHorizontalScroller = false
        mainScrollView.autohidesScrollers = true
        mainScrollView.verticalScrollElasticity = .none
        mainScrollView.automaticallyAdjustsContentInsets = true
        mainScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(mainScrollView)

        let documentView = RulesPrototypeFlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.postsFrameChangedNotifications = true
        mainScrollView.documentView = documentView
        mainScrollView.contentView.postsBoundsChangedNotifications = true
        mainScrollView.contentView.postsFrameChangedNotifications = true

        settingsContent.orientation = .vertical
        settingsContent.alignment = .leading
        settingsContent.spacing = 22
        settingsContent.translatesAutoresizingMaskIntoConstraints = false
        settingsContent.setContentHuggingPriority(.required, for: .vertical)
        settingsContent.setContentCompressionResistancePriority(.required, for: .vertical)
        documentView.addSubview(settingsContent)

        topScrollEdgeView.translatesAutoresizingMaskIntoConstraints = false
        bottomScrollEdgeView.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(topScrollEdgeView)
        detailContainer.addSubview(bottomScrollEdgeView)

        let documentPreferredHeight = documentView.heightAnchor
            .constraint(equalTo: mainScrollView.contentView.heightAnchor)
        documentPreferredHeight.priority = .defaultLow

        let scrollTopConstraint: NSLayoutConstraint
        if #available(macOS 11.0, *) {
            scrollTopConstraint = mainScrollView.topAnchor
                .constraint(equalTo: detailContainer.safeAreaLayoutGuide.topAnchor)
        } else {
            scrollTopConstraint = mainScrollView.topAnchor.constraint(equalTo: detailContainer.topAnchor)
        }

        NSLayoutConstraint.activate([
            scrollTopConstraint,
            mainScrollView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            mainScrollView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            mainScrollView.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
            settingsContent.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 32),
            settingsContent.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 32),
            settingsContent.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -32),
            documentView.bottomAnchor.constraint(greaterThanOrEqualTo: settingsContent.bottomAnchor, constant: 40),
            documentView.widthAnchor.constraint(equalTo: mainScrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: mainScrollView.contentView.heightAnchor),
            documentPreferredHeight,
            topScrollEdgeView.topAnchor.constraint(equalTo: mainScrollView.topAnchor),
            topScrollEdgeView.leadingAnchor.constraint(equalTo: mainScrollView.leadingAnchor),
            topScrollEdgeView.trailingAnchor.constraint(equalTo: mainScrollView.trailingAnchor),
            topScrollEdgeView.heightAnchor.constraint(equalToConstant: 34),
            bottomScrollEdgeView.leadingAnchor.constraint(equalTo: mainScrollView.leadingAnchor),
            bottomScrollEdgeView.trailingAnchor.constraint(equalTo: mainScrollView.trailingAnchor),
            bottomScrollEdgeView.bottomAnchor.constraint(equalTo: mainScrollView.bottomAnchor),
            bottomScrollEdgeView.heightAnchor.constraint(equalToConstant: 34)
        ])

        installScrollEdgeObservers()
    }

    private func installScrollEdgeObservers() {
        let center = NotificationCenter.default
        scrollEdgeObservers.append(center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: mainScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateScrollEdgeEffects()
        })
        scrollEdgeObservers.append(center.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: mainScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateScrollEdgeEffects()
        })
        if let documentView = mainScrollView.documentView {
            scrollEdgeObservers.append(center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateScrollEdgeEffects()
            })
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateScrollEdgeEffects()
        }
    }

    private func updateScrollEdgeEffects() {
        guard let documentView = mainScrollView.documentView else {
            topScrollEdgeView.alphaValue = 0
            bottomScrollEdgeView.alphaValue = 0
            return
        }

        let visibleRect = mainScrollView.contentView.bounds
        let contentHeight = max(documentView.frame.height, documentView.bounds.height)
        let hasOverflow = contentHeight > visibleRect.height + 1
        let isAwayFromTop = visibleRect.minY > 1
        let hasMoreBelow = visibleRect.maxY < contentHeight - 1

        topScrollEdgeView.alphaValue = hasOverflow && isAwayFromTop ? 1 : 0
        bottomScrollEdgeView.alphaValue = hasOverflow && hasMoreBelow ? 1 : 0
    }

    private func configureSidebarTableView() {
        sidebarTableView.headerView = nil
        sidebarTableView.backgroundColor = .clear
        sidebarTableView.rowSizeStyle = .custom
        sidebarTableView.intercellSpacing = .zero
        sidebarTableView.gridStyleMask = []
        sidebarTableView.usesAlternatingRowBackgroundColors = false
        sidebarTableView.selectionHighlightStyle = .none
        sidebarTableView.allowsEmptySelection = false
        sidebarTableView.allowsMultipleSelection = false
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self
        sidebarTableView.autoresizingMask = [.width]
        sidebarTableView.focusRingType = .none
        if #available(macOS 11.0, *) {
            sidebarTableView.style = .plain
        }

        let column = NSTableColumn(identifier: RulesPrototypeSidebarListRow.columnIdentifier)
        column.resizingMask = .autoresizingMask
        column.minWidth = 1
        column.width = 230
        sidebarTableView.addTableColumn(column)
    }

    private func bindState() {
        configurationState.$configuration
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configurationDidChange()
            }
            .store(in: &subscriptions)

        deviceState.$currentDeviceRef
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderAll()
            }
            .store(in: &subscriptions)
    }

    private func configurationDidChange() {
        normalizeSelection()
        selectVisibleRuleIfNeeded()
        renderAll()
    }

    private func renderAll() {
        renderRulePicker()
        renderSidebar()
        renderSettings()
    }

    private func renderRulePicker() {
        guard let selectedScheme else {
            rulePickerButton.configure(
                title: NSLocalizedString("Rules", comment: ""),
                subtitle: NSLocalizedString("No rule selected", comment: ""),
                symbol: "slider.horizontal.3"
            )
            return
        }

        rulePickerButton.configure(
            title: RulesPrototypePresenter.title(for: selectedScheme, at: selectedRuleIndex),
            subtitle: RulesPrototypePresenter.targetSummary(for: selectedScheme),
            symbol: RulesPrototypePresenter.symbol(for: selectedScheme)
        )
    }

    private func renderSidebar() {
        guard let selectedScheme else {
            isUpdatingSidebarSelection = true
            defer {
                isUpdatingSidebarSelection = false
            }
            sidebarRows = []
            sidebarTableView.reloadData()
            return
        }

        sidebarRows = RulesPrototypeSettingGroup.allCases.flatMap { group in
            [RulesPrototypeSidebarListRow.group(group)] + RulesPrototypeSettingsSection.sections(for: group)
                .map { section in
                    .section(section, hasSettings: section.keys.contains { $0.isSet(in: selectedScheme) })
                }
        }
        isUpdatingSidebarSelection = true
        defer {
            isUpdatingSidebarSelection = false
        }
        sidebarTableView.reloadData()
        selectSidebarRow()
    }

    private func selectSidebarRow() {
        guard let row = sidebarRows.firstIndex(where: {
            if case let .section(section, _) = $0 {
                return section.id == selectedSectionID
            }
            return false
        }) else {
            return
        }

        sidebarTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        sidebarTableView.scrollRowToVisible(row)
    }

    func numberOfRows(in _: NSTableView) -> Int {
        sidebarRows.count
    }

    func tableView(_: NSTableView, isGroupRow _: Int) -> Bool {
        false
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard sidebarRows.indices.contains(row) else {
            return false
        }
        if case .section = sidebarRows[row] {
            return true
        }
        return false
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard sidebarRows.indices.contains(row) else {
            return 32
        }
        switch sidebarRows[row] {
        case .group:
            return 30
        case .section:
            return 38
        }
    }

    func tableView(_: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let isGroup = sidebarRows.indices.contains(row) && {
            if case .group = sidebarRows[row] {
                return true
            }
            return false
        }()
        return RulesPrototypeSidebarTableRowView(isGroupRow: isGroup)
    }

    func tableView(
        _: NSTableView,
        viewFor _: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard sidebarRows.indices.contains(row) else {
            return nil
        }

        switch sidebarRows[row] {
        case let .group(group):
            return RulesPrototypeSidebarHeadingCell(title: group.title)
        case let .section(section, hasSettings):
            return RulesPrototypeSidebarSectionCell(
                title: section.title,
                symbol: section.symbol,
                selected: section.id == selectedSectionID,
                hasSettings: hasSettings
            )
        }
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isUpdatingSidebarSelection else {
            return
        }

        let row = sidebarTableView.selectedRow
        guard sidebarRows.indices.contains(row),
              case let .section(section, _) = sidebarRows[row] else {
            return
        }

        guard selectedSectionID != section.id else {
            return
        }
        selectSidebarSection(section.id)
    }

    private func selectSidebarSection(_ sectionID: String) {
        selectedSectionID = sectionID
        renderSettings()
        refreshSidebarRowsKeepingSelection()
    }

    private func refreshSidebarRowsKeepingSelection() {
        guard !sidebarRows.isEmpty, sidebarTableView.numberOfColumns > 0 else {
            return
        }

        isUpdatingSidebarSelection = true
        defer {
            isUpdatingSidebarSelection = false
        }
        sidebarTableView.reloadData(
            forRowIndexes: IndexSet(integersIn: 0 ..< sidebarRows.count),
            columnIndexes: IndexSet(integer: 0)
        )
        selectSidebarRow()
    }

    private func renderSettings() {
        rpRemoveArrangedSubviews(from: settingsContent)

        guard let section = selectedSection(), let selectedScheme else {
            renderedSectionID = nil
            settingsContent.addArrangedSubview(makeEmptyState(
                title: NSLocalizedString("No Rule Selected", comment: ""),
                message: NSLocalizedString("Choose or create a rule to edit its settings.", comment: "")
            ))
            return
        }

        let shouldResetScrollPosition = renderedSectionID != section.id
        renderedSectionID = section.id

        settingsContent.addArrangedSubview(makeHeader(section: section, scheme: selectedScheme))
        settingsContent.addArrangedSubview(makeSettingGroupPanel(section: section, scheme: selectedScheme))
        DispatchQueue.main.async { [weak self] in
            if shouldResetScrollPosition {
                self?.scrollSettingsToTop()
            }
            self?.updateScrollEdgeEffects()
        }
    }

    private func scrollSettingsToTop() {
        mainScrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        mainScrollView.reflectScrolledClipView(mainScrollView.contentView)
    }

    private func makeHeader(section: RulesPrototypeSettingsSection, scheme: Scheme) -> NSView {
        let wrapper = NSStackView()
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 4
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: 760).isActive = true

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 12
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        titleRow.addArrangedSubview(rpLabel(section.title, size: 23, color: .labelColor, weight: .semibold))
        titleRow.addArrangedSubview(rpFlexibleSpace())

        if section.keys.contains(where: { $0.isSet(in: scheme) }) {
            let unset = RulesPrototypeInlineButton(
                title: NSLocalizedString("Unset Group", comment: ""),
                target: self,
                action: #selector(unsetSettingsSection(_:))
            )
            unset.identifier = NSUserInterfaceItemIdentifier(section.id)
            titleRow.addArrangedSubview(unset)
        }

        wrapper.addArrangedSubview(titleRow)

        let subtitleLabel = rpLabel(
            "\(section.group.title) · \(RulesPrototypePresenter.title(for: scheme, at: selectedRuleIndex))",
            size: 12,
            color: .secondaryLabelColor,
            weight: .medium
        )
        wrapper.addArrangedSubview(subtitleLabel)

        return wrapper
    }

    private func makeSettingGroupPanel(section: RulesPrototypeSettingsSection, scheme: Scheme) -> NSView {
        let panel = RulesPrototypeCardView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.widthAnchor.constraint(equalToConstant: 760).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        rpPin(stack, to: panel)

        for (index, key) in section.keys.enumerated() {
            stack.addArrangedSubview(makeSettingRow(key, scheme: scheme))
            if index < section.keys.count - 1 {
                stack.addArrangedSubview(makeInsetDivider(width: 760, leading: 18))
            }
        }

        return panel
    }

    private func makeSettingRow(_ key: RulesPrototypeSettingKey, scheme: Scheme) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 760).isActive = true
        row.alphaValue = key.isSet(in: scheme) ? 1 : 0.86

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        content.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(content)
        rpPin(content, to: row)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        header.addArrangedSubview(rpPlainSymbolView(
            key.symbol,
            color: key.isSet(in: scheme) ? RulesPrototypePalette.accent : .tertiaryLabelColor
        ))

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(rpLabel(key.title, size: 13, weight: .semibold))
        textStack.addArrangedSubview(rpLabel(key.shortDescription, size: 12, color: .secondaryLabelColor))
        header.addArrangedSubview(textStack)
        header.addArrangedSubview(rpFlexibleSpace())

        if key.isSet(in: scheme) {
            let unset = RulesPrototypeInlineButton(
                title: NSLocalizedString("Unset", comment: ""),
                target: self,
                action: #selector(unsetSetting(_:))
            )
            unset.identifier = NSUserInterfaceItemIdentifier(key.rawValue)
            header.addArrangedSubview(unset)
        }

        content.addArrangedSubview(header)

        let controls = makeControls(for: key)
        let controlsRow = rpHorizontalStack(spacing: 0)
        let inset = NSView()
        inset.translatesAutoresizingMaskIntoConstraints = false
        inset.widthAnchor.constraint(equalToConstant: 34).isActive = true
        controlsRow.addArrangedSubview(inset)
        controlsRow.addArrangedSubview(controls)
        controlsRow.addArrangedSubview(rpFlexibleSpace())
        content.addArrangedSubview(controlsRow)
        return row
    }

    private func makeControls(for key: RulesPrototypeSettingKey) -> NSView {
        switch key {
        case .pointerSpeed:
            return makeDecimalSlider(
                identifier: key.rawValue,
                value: pointerSpeedValue,
                range: 0 ... 1,
                suffix: nil
            )
        case .pointerAcceleration:
            return makePointerAccelerationControls()
        case .redirectsToScroll:
            return makeCheckbox(
                identifier: key.rawValue,
                title: "",
                value: redirectsToScrollValue
            )
        case .reverseVertical:
            return makeCheckbox(
                identifier: key.rawValue,
                title: "",
                value: reverseVerticalValue
            )
        case .reverseHorizontal:
            return makeCheckbox(
                identifier: key.rawValue,
                title: "",
                value: reverseHorizontalValue
            )
        case .scrollMode:
            return makeScrollModeControls()
        case .scrollModifiers:
            return makeScrollModifiersControls()
        case .universalBackForward:
            return makeUniversalBackForwardControls()
        case .buttonMappings:
            return makeButtonMappingsControls()
        case .autoScroll:
            return makeAutoScrollControls()
        case .gesture:
            return makeGestureControls()
        case .switchPrimary:
            return makeCheckbox(
                identifier: key.rawValue,
                title: "",
                value: switchPrimaryValue
            )
        case .clickDebouncing:
            return makeClickDebouncingControls()
        case .disablePointerAcceleration, .scrollDistance, .scrollDistanceHorizontal, .scrollAcceleration,
             .scrollAccelerationHorizontal, .scrollSpeed, .scrollSpeedHorizontal, .smoothedScrolling,
             .autoScrollOptions, .gestureOptions:
            return rpLabel(
                NSLocalizedString("This setting is edited through its parent control.", comment: ""),
                color: .secondaryLabelColor
            )
        }
    }

    private func makePointerAccelerationControls() -> NSView {
        let stack = rpVerticalStack(spacing: 10)
        let checkbox = makeCheckbox(
            identifier: "pointerAcceleration.disabled",
            title: NSLocalizedString("Disable pointer acceleration", comment: ""),
            value: disablePointerAccelerationValue
        )
        stack.addArrangedSubview(checkbox)

        let slider = makeDecimalSlider(
            identifier: RulesPrototypeSettingKey.pointerAcceleration.rawValue,
            value: pointerAccelerationValue,
            range: 0 ... 20,
            suffix: nil
        )
        slider.alphaValue = disablePointerAccelerationValue ? 0.45 : 1
        stack.addArrangedSubview(slider)
        return stack
    }

    private func makeScrollModeControls() -> NSView {
        let stack = rpVerticalStack(spacing: 12)

        let segmented = NSSegmentedControl(
            labels: RulesPrototypeScrollMode.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(segmentedChanged(_:))
        )
        segmented.identifier = NSUserInterfaceItemIdentifier("scrollMode")
        segmented.selectedSegment = RulesPrototypeScrollMode.allCases.firstIndex(of: scrollModeValue) ?? 0
        segmented.segmentStyle = .rounded
        segmented.controlSize = .regular
        segmented.font = .systemFont(ofSize: 13, weight: .medium)
        segmented.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(segmented)

        switch scrollModeValue {
        case .accelerated:
            stack.addArrangedSubview(makeDecimalSlider(
                identifier: "scroll.acceleration.vertical",
                value: verticalScrollAccelerationValue,
                range: 0 ... 10,
                suffix: NSLocalizedString("vertical acceleration", comment: "")
            ))
            stack.addArrangedSubview(makeDecimalSlider(
                identifier: "scroll.speed.vertical",
                value: verticalScrollSpeedValue,
                range: 0 ... 128,
                suffix: NSLocalizedString("vertical speed", comment: "")
            ))
            stack.addArrangedSubview(makeDecimalSlider(
                identifier: "scroll.acceleration.horizontal",
                value: horizontalScrollAccelerationValue,
                range: 0 ... 10,
                suffix: NSLocalizedString("horizontal acceleration", comment: "")
            ))
            stack.addArrangedSubview(makeDecimalSlider(
                identifier: "scroll.speed.horizontal",
                value: horizontalScrollSpeedValue,
                range: 0 ... 128,
                suffix: NSLocalizedString("horizontal speed", comment: "")
            ))

        case .linear:
            let unit = NSPopUpButton()
            rpStylePopup(unit)
            unit.identifier = NSUserInterfaceItemIdentifier("scroll.linearUnit")
            for value in RulesPrototypeLinearScrollUnit.allCases {
                unit.addItem(withTitle: value.title)
                unit.lastItem?.representedObject = value.rawValue
            }
            unit.selectItem(withTitle: linearScrollUnitValue.title)
            unit.target = self
            unit.action = #selector(popupChanged(_:))
            stack.addArrangedSubview(unit)

            switch linearScrollUnitValue {
            case .lines:
                stack.addArrangedSubview(makeIntegerStepper(
                    identifier: "scroll.distance.vertical.lines",
                    value: verticalDistanceValue,
                    range: 0 ... 10,
                    suffix: NSLocalizedString("vertical lines", comment: "")
                ))
                stack.addArrangedSubview(makeIntegerStepper(
                    identifier: "scroll.distance.horizontal.lines",
                    value: horizontalDistanceValue,
                    range: 0 ... 10,
                    suffix: NSLocalizedString("horizontal lines", comment: "")
                ))
            case .pixels:
                stack.addArrangedSubview(makeDecimalSlider(
                    identifier: "scroll.distance.vertical.pixels",
                    value: verticalPixelDistanceValue,
                    range: 0 ... 128,
                    suffix: NSLocalizedString("vertical pixels", comment: "")
                ))
                stack.addArrangedSubview(makeDecimalSlider(
                    identifier: "scroll.distance.horizontal.pixels",
                    value: horizontalPixelDistanceValue,
                    range: 0 ... 128,
                    suffix: NSLocalizedString("horizontal pixels", comment: "")
                ))
            }

        case .smoothed:
            let preset = NSPopUpButton()
            rpStylePopup(preset)
            preset.identifier = NSUserInterfaceItemIdentifier("scroll.smoothed.preset")
            for value in Scheme.Scrolling.Smoothed.Preset.recommendedCases {
                preset.addItem(withTitle: RulesPrototypePresenter.smoothedPresetTitle(value))
                preset.lastItem?.representedObject = value.rawValue
            }
            preset.selectItem(withTitle: RulesPrototypePresenter.smoothedPresetTitle(smoothedPresetValue))
            preset.target = self
            preset.action = #selector(popupChanged(_:))
            stack.addArrangedSubview(preset)
            stack.addArrangedSubview(makeDecimalSlider(
                identifier: "scroll.smoothed.response",
                value: smoothedResponseValue,
                range: Scheme.Scrolling.Smoothed.responseRange,
                suffix: NSLocalizedString("response", comment: "")
            ))
            stack.addArrangedSubview(makeDecimalSlider(
                identifier: "scroll.smoothed.speed",
                value: smoothedSpeedValue,
                range: Scheme.Scrolling.Smoothed.speedRange,
                suffix: NSLocalizedString("speed", comment: "")
            ))
            stack.addArrangedSubview(makeDecimalSlider(
                identifier: "scroll.smoothed.acceleration",
                value: smoothedAccelerationValue,
                range: Scheme.Scrolling.Smoothed.accelerationRange,
                suffix: NSLocalizedString("acceleration", comment: "")
            ))
            stack.addArrangedSubview(makeDecimalSlider(
                identifier: "scroll.smoothed.inertia",
                value: smoothedInertiaValue,
                range: Scheme.Scrolling.Smoothed.inertiaRange,
                suffix: NSLocalizedString("inertia", comment: "")
            ))
            stack.addArrangedSubview(makeCheckbox(
                identifier: "scroll.smoothed.bouncing",
                title: NSLocalizedString("Allow bouncing", comment: ""),
                value: smoothedBouncingValue
            ))
        }

        return stack
    }

    private func makeScrollModifiersControls() -> NSView {
        let stack = rpVerticalStack(spacing: 14)
        stack.addArrangedSubview(makeModifierSection(
            title: NSLocalizedString("Vertical", comment: ""),
            direction: .vertical
        ))
        stack.addArrangedSubview(makeModifierSection(
            title: NSLocalizedString("Horizontal", comment: ""),
            direction: .horizontal
        ))
        return stack
    }

    private func makeModifierSection(title: String, direction: Scheme.Scrolling.BidirectionalDirection) -> NSView {
        let stack = rpVerticalStack(spacing: 8)
        stack.addArrangedSubview(rpLabel(title, size: 11, color: .secondaryLabelColor, weight: .semibold))
        let rows: [(String, WritableKeyPath<Scheme.Scrolling.Modifiers, Scheme.Scrolling.Modifiers.Action?>)] = [
            ("⌘ Command", \.command),
            ("⇧ Shift", \.shift),
            ("⌥ Option", \.option),
            ("⌃ Control", \.control)
        ]
        for (label, keyPath) in rows {
            let row = rpHorizontalStack(spacing: 10)
            row.addArrangedSubview(rpLabel(label, width: 120))
            let popup = NSPopUpButton()
            rpStylePopup(popup)
            popup.identifier = NSUserInterfaceItemIdentifier("modifier.\(direction.rawValue).\(label)")
            popup.target = self
            popup.action = #selector(popupChanged(_:))
            popup.addItem(withTitle: NSLocalizedString("Follow earlier rules", comment: ""))
            popup.lastItem?.representedObject = RulesPrototypeModifierChoice.inherit.rawValue
            for choice in RulesPrototypeModifierChoice.actionCases {
                popup.addItem(withTitle: choice.title)
                popup.lastItem?.representedObject = choice.rawValue
            }
            let current = modifierAction(direction: direction, keyPath: keyPath)
            let selectedChoice = RulesPrototypeModifierChoice(action: current)
            popup.selectItem(withTitle: selectedChoice.title)
            popup.tag = RulesPrototypeModifierField(direction: direction, label: label).tag
            row.addArrangedSubview(popup)
            row.addArrangedSubview(rpFlexibleSpace())
            stack.addArrangedSubview(row)
        }
        return stack
    }

    private func makeUniversalBackForwardControls() -> NSView {
        let popup = NSPopUpButton()
        rpStylePopup(popup)
        popup.identifier = NSUserInterfaceItemIdentifier(RulesPrototypeSettingKey.universalBackForward.rawValue)
        for choice in RulesPrototypeUniversalBackForwardChoice.allCases {
            popup.addItem(withTitle: choice.title)
            popup.lastItem?.representedObject = choice.rawValue
        }
        popup.selectItem(withTitle: universalBackForwardChoice.title)
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        return popup
    }

    private func makeButtonMappingsControls() -> NSView {
        let stack = rpVerticalStack(spacing: 10)
        let mappings = selectedScheme?.buttons.mappings ?? []

        if mappings.isEmpty {
            stack.addArrangedSubview(rpLabel(
                NSLocalizedString("No custom mappings in this rule.", comment: ""),
                color: .secondaryLabelColor
            ))
        } else {
            for (index, mapping) in mappings.enumerated() {
                stack.addArrangedSubview(makeMappingRow(mapping, index: index))
            }
        }

        let add = NSButton(
            title: NSLocalizedString("Add Mapping", comment: ""),
            target: self,
            action: #selector(addButtonMapping)
        )
        rpStyleActionButton(add)
        stack.addArrangedSubview(add)
        return stack
    }

    private func makeMappingRow(_ mapping: Scheme.Buttons.Mapping, index: Int) -> NSView {
        let container = rpVerticalStack(spacing: 8)
        let row = rpHorizontalStack(spacing: 10)
        let record = NSButton(
            title: RulesPrototypePresenter.mappingTargetTitle(mapping),
            target: self,
            action: #selector(recordMappingButton(_:))
        )
        record.tag = index
        rpStyleActionButton(record)
        record.widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
        row.addArrangedSubview(record)

        let action = NSPopUpButton()
        rpStylePopup(action)
        action.identifier = NSUserInterfaceItemIdentifier("mapping.action.\(index)")
        for choice in RulesPrototypeMappingActionChoice.all {
            action.addItem(withTitle: choice.title)
            action.lastItem?.representedObject = choice
        }
        action.selectItem(withTitle: RulesPrototypeMappingActionChoice.choice(for: mapping.action).title)
        action.target = self
        action.action = #selector(popupChanged(_:))
        row.addArrangedSubview(action)

        row.addArrangedSubview(rpFlexibleSpace())
        let remove = NSButton(
            title: NSLocalizedString("Remove", comment: ""),
            target: self,
            action: #selector(removeButtonMapping(_:))
        )
        rpStyleActionButton(remove)
        remove.tag = index
        row.addArrangedSubview(remove)
        container.addArrangedSubview(row)

        if let detail = makeMappingActionDetail(mapping, index: index) {
            container.addArrangedSubview(detail)
        }
        return container
    }

    private func makeMappingActionDetail(_ mapping: Scheme.Buttons.Mapping, index: Int) -> NSView? {
        guard let action = mapping.action else {
            return nil
        }

        let row = rpHorizontalStack(spacing: 10)
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 142).isActive = true
        row.addArrangedSubview(spacer)

        switch action {
        case let .arg1(.run(command)):
            let field = NSTextField(string: command)
            field.identifier = NSUserInterfaceItemIdentifier("mapping.run.\(index)")
            field.placeholderString = NSLocalizedString("Command", comment: "")
            field.delegate = self
            field.target = self
            field.action = #selector(mappingRunCommandCommitted(_:))
            rpStyleInputField(field)
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 320).isActive = true
            row.addArrangedSubview(field)

        case let .arg1(.keyPress(keys)):
            let record = NSButton(
                title: RulesPrototypePresenter.keyPressTitle(keys),
                target: self,
                action: #selector(recordMappingKeyPress(_:))
            )
            record.tag = index
            rpStyleActionButton(record)
            record.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
            row.addArrangedSubview(record)

            if mapping.button != nil {
                row.addArrangedSubview(makeKeyPressBehaviorPopup(mapping, index: index))
            }

        case .arg1(.mouseWheelScrollUp),
             .arg1(.mouseWheelScrollDown),
             .arg1(.mouseWheelScrollLeft),
             .arg1(.mouseWheelScrollRight):
            row.addArrangedSubview(rpLabel(
                action.description,
                size: 12,
                color: .secondaryLabelColor,
                weight: .medium
            ))

        case .arg0:
            if mapping.button != nil {
                row.addArrangedSubview(makeCheckbox(
                    identifier: "mapping.repeat.\(index)",
                    title: NSLocalizedString("Repeat on hold", comment: ""),
                    value: mapping.repeat ?? false
                ))
            } else {
                return nil
            }
        }

        row.addArrangedSubview(rpFlexibleSpace())
        return row
    }

    private func makeKeyPressBehaviorPopup(_ mapping: Scheme.Buttons.Mapping, index: Int) -> NSView {
        let popup = NSPopUpButton()
        rpStylePopup(popup)
        popup.identifier = NSUserInterfaceItemIdentifier("mapping.keyBehavior.\(index)")
        for behavior in Scheme.Buttons.Mapping.KeyPressBehavior.allCases {
            popup.addItem(withTitle: RulesPrototypePresenter.keyPressBehaviorTitle(behavior))
            popup.lastItem?.representedObject = behavior.rawValue
        }
        popup.selectItem(withTitle: RulesPrototypePresenter.keyPressBehaviorTitle(mapping.keyPressBehavior))
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        return popup
    }

    private func makeAutoScrollControls() -> NSView {
        let stack = rpVerticalStack(spacing: 10)
        stack.addArrangedSubview(makeSwitchRow(
            identifier: "autoScroll.enabled",
            title: NSLocalizedString("Enable auto scroll", comment: ""),
            value: autoScrollValue
        ))

        let record = NSButton(
            title: RulesPrototypePresenter.mappingTargetTitle(autoScrollTriggerValue),
            target: self,
            action: #selector(recordAutoScrollTrigger(_:))
        )
        rpStyleActionButton(record)
        stack.addArrangedSubview(record)

        let modeRow = rpHorizontalStack(spacing: 16)
        modeRow.addArrangedSubview(makeCheckbox(
            identifier: "autoScroll.mode.toggle",
            title: NSLocalizedString("Toggle", comment: ""),
            value: autoScrollModesValue.contains(.toggle)
        ))
        modeRow.addArrangedSubview(makeCheckbox(
            identifier: "autoScroll.mode.hold",
            title: NSLocalizedString("Hold", comment: ""),
            value: autoScrollModesValue.contains(.hold)
        ))
        modeRow.addArrangedSubview(rpFlexibleSpace())
        stack.addArrangedSubview(modeRow)

        stack.addArrangedSubview(makeDecimalSlider(
            identifier: "autoScroll.speed",
            value: autoScrollSpeedValue,
            range: 0 ... 10,
            suffix: NSLocalizedString("speed", comment: "")
        ))
        stack.addArrangedSubview(makeCheckbox(
            identifier: "autoScroll.preserveNativeMiddleClick",
            title: NSLocalizedString("Keep native middle-click behavior", comment: ""),
            value: autoScrollPreserveNativeMiddleClickValue
        ))
        return stack
    }

    private func makeGestureControls() -> NSView {
        let stack = rpVerticalStack(spacing: 10)
        stack.addArrangedSubview(makeSwitchRow(
            identifier: "gesture.enabled",
            title: NSLocalizedString("Enable gesture button", comment: ""),
            value: gestureValue
        ))

        let record = NSButton(
            title: RulesPrototypePresenter.mappingTargetTitle(gestureTriggerValue),
            target: self,
            action: #selector(recordGestureTrigger(_:))
        )
        rpStyleActionButton(record)
        stack.addArrangedSubview(record)

        stack.addArrangedSubview(makeIntegerStepper(
            identifier: "gesture.threshold",
            value: gestureThresholdValue,
            range: 0 ... 200,
            suffix: NSLocalizedString("threshold", comment: "")
        ))

        let actions = [
            (
                NSLocalizedString("Left", comment: ""),
                "gesture.action.left",
                gestureActionValue(\.left, fallback: .spaceLeft)
            ),
            (
                NSLocalizedString("Right", comment: ""),
                "gesture.action.right",
                gestureActionValue(\.right, fallback: .spaceRight)
            ),
            (
                NSLocalizedString("Up", comment: ""),
                "gesture.action.up",
                gestureActionValue(\.up, fallback: .missionControl)
            ),
            (
                NSLocalizedString("Down", comment: ""),
                "gesture.action.down",
                gestureActionValue(\.down, fallback: .appExpose)
            )
        ]
        for (title, identifier, value) in actions {
            let row = rpHorizontalStack(spacing: 10)
            row.addArrangedSubview(rpLabel(title, width: 80))
            let popup = NSPopUpButton()
            rpStylePopup(popup)
            popup.identifier = NSUserInterfaceItemIdentifier(identifier)
            for action in Scheme.Buttons.Gesture.GestureAction.allCases {
                popup.addItem(withTitle: RulesPrototypePresenter.gestureActionTitle(action))
                popup.lastItem?.representedObject = action.rawValue
            }
            popup.selectItem(withTitle: RulesPrototypePresenter.gestureActionTitle(value))
            popup.target = self
            popup.action = #selector(popupChanged(_:))
            row.addArrangedSubview(popup)
            row.addArrangedSubview(rpFlexibleSpace())
            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func makeClickDebouncingControls() -> NSView {
        let stack = rpVerticalStack(spacing: 10)
        stack.addArrangedSubview(makeIntegerStepper(
            identifier: "clickDebouncing.timeout",
            value: clickDebouncingTimeoutValue,
            range: 0 ... 1000,
            suffix: NSLocalizedString("ms", comment: "")
        ))
        stack.addArrangedSubview(makeCheckbox(
            identifier: "clickDebouncing.resetOnMouseUp",
            title: NSLocalizedString("Reset timer when the button is released", comment: ""),
            value: clickDebouncingResetTimerOnMouseUpValue
        ))

        let buttonsRow = rpHorizontalStack(spacing: 12)
        for option in RulesPrototypeMouseButtonOption.debouncingButtons {
            buttonsRow.addArrangedSubview(makeCheckbox(
                identifier: "clickDebouncing.button.\(option.button.rawValue)",
                title: option.title,
                value: clickDebouncingButtonsValue.contains(option.button)
            ))
        }
        buttonsRow.addArrangedSubview(rpFlexibleSpace())
        stack.addArrangedSubview(buttonsRow)
        return stack
    }

    private func makeDecimalSlider(
        identifier: String,
        value: Double,
        range: ClosedRange<Double>,
        suffix: String?
    ) -> NSView {
        let row = rpHorizontalStack(spacing: 10)
        let slider = NSSlider(
            value: value.clamped(to: range),
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: self,
            action: #selector(decimalSliderChanged(_:))
        )
        slider.identifier = NSUserInterfaceItemIdentifier(identifier)
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        row.addArrangedSubview(slider)

        let field = NSTextField(string: RulesPrototypePresenter.doubleString(value))
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.delegate = self
        field.target = self
        field.action = #selector(decimalFieldCommitted(_:))
        field.alignment = .right
        rpStyleInputField(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
        row.addArrangedSubview(field)
        if let suffix, !suffix.isEmpty {
            row.addArrangedSubview(rpLabel(suffix, size: 12, color: .secondaryLabelColor))
        }
        row.addArrangedSubview(rpFlexibleSpace())
        return row
    }

    private func makeIntegerStepper(identifier: String, value: Int, range: ClosedRange<Int>, suffix: String) -> NSView {
        let row = rpHorizontalStack(spacing: 8)
        let stepper = NSStepper()
        stepper.doubleValue = Double(value)
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.target = self
        stepper.action = #selector(integerStepperChanged(_:))
        stepper.identifier = NSUserInterfaceItemIdentifier(identifier)
        row.addArrangedSubview(stepper)

        let field = NSTextField(string: "\(value)")
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.delegate = self
        field.target = self
        field.action = #selector(integerFieldCommitted(_:))
        field.alignment = .right
        rpStyleInputField(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
        row.addArrangedSubview(field)
        row.addArrangedSubview(rpLabel(suffix, size: 12, color: .secondaryLabelColor))
        row.addArrangedSubview(rpFlexibleSpace())
        return row
    }

    private func makeCheckbox(identifier: String, title: String, value: Bool) -> NSView {
        if title.isEmpty {
            return makeSwitch(identifier: identifier, value: value)
        }

        let row = rpHorizontalStack(spacing: 9)
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(identifier)
        checkbox.state = value ? .on : .off
        checkbox.controlSize = .regular
        checkbox.font = .systemFont(ofSize: 13, weight: .regular)
        checkbox.contentTintColor = .labelColor
        checkbox.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(checkbox)
        row.addArrangedSubview(rpFlexibleSpace())
        return row
    }

    private func makeSwitchRow(identifier: String, title: String, value: Bool) -> NSView {
        let row = rpHorizontalStack(spacing: 10)
        row.alignment = .centerY
        row.addArrangedSubview(makeSwitch(identifier: identifier, value: value))
        row.addArrangedSubview(rpLabel(title, size: 13, color: .labelColor, weight: .regular))
        row.addArrangedSubview(rpFlexibleSpace())
        return row
    }

    private func makeSwitch(identifier: String, value: Bool) -> NSControl {
        if #available(macOS 10.15, *) {
            let toggle = NSSwitch()
            toggle.identifier = NSUserInterfaceItemIdentifier(identifier)
            toggle.state = value ? .on : .off
            toggle.target = self
            toggle.action = #selector(checkboxChanged(_:))
            toggle.controlSize = .regular
            toggle.translatesAutoresizingMaskIntoConstraints = false
            toggle.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
            return toggle
        }

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxChanged(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(identifier)
        checkbox.state = value ? .on : .off
        return checkbox
    }

    private func makeEmptyState(title: String, message: String) -> NSView {
        let card = RulesPrototypeCardView()
        let stack = rpVerticalStack(spacing: 6)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.addArrangedSubview(rpLabel(title, size: 18, weight: .semibold))
        stack.addArrangedSubview(rpLabel(message, color: .secondaryLabelColor))
        card.addSubview(stack)
        rpPin(stack, to: card)
        return card
    }

    private func selectedSection() -> RulesPrototypeSettingsSection? {
        let all = RulesPrototypeSettingGroup.allCases.flatMap(RulesPrototypeSettingsSection.sections)
        return all.first { $0.id == selectedSectionID } ?? all.first
    }

    private func inheritedSourceText(for key: RulesPrototypeSettingKey) -> String {
        guard let source = inheritedRuleTitle(for: key) else {
            return NSLocalizedString("Default", comment: "")
        }
        return String(format: NSLocalizedString("From %@", comment: ""), source)
    }

    private func inheritedRuleTitle(for key: RulesPrototypeSettingKey) -> String? {
        guard schemes.indices.contains(selectedRuleIndex) else {
            return nil
        }
        for index in stride(from: selectedRuleIndex - 1, through: 0, by: -1) {
            guard schemes.indices.contains(index), key.isSet(in: schemes[index]) else {
                continue
            }
            return RulesPrototypePresenter.title(for: schemes[index], at: index)
        }
        return nil
    }

    private func mergedSchemeBeforeSelectedRule() -> Scheme {
        var merged = Scheme()
        for (index, scheme) in schemes.enumerated() where index < selectedRuleIndex {
            scheme.merge(into: &merged)
        }
        return merged
    }

    private var effectiveSchemeForEditing: Scheme {
        mergedSchemeBeforeSelectedRule()
    }

    private var pointerSpeedValue: Double {
        RulesPrototypePresenter.doubleValue(
            selectedScheme?.pointer.speed ?? effectiveSchemeForEditing.pointer.speed,
            fallback: 0.5
        )
    }

    private var pointerAccelerationValue: Double {
        RulesPrototypePresenter.doubleValue(
            selectedScheme?.pointer.acceleration ?? effectiveSchemeForEditing.pointer.acceleration,
            fallback: 0
        )
    }

    private var disablePointerAccelerationValue: Bool {
        selectedScheme?.pointer.disableAcceleration ?? effectiveSchemeForEditing.pointer.disableAcceleration ?? false
    }

    private var redirectsToScrollValue: Bool {
        selectedScheme?.pointer.redirectsToScroll ?? effectiveSchemeForEditing.pointer.redirectsToScroll ?? false
    }

    private var reverseVerticalValue: Bool {
        selectedScheme?.scrolling.reverse.vertical ?? effectiveSchemeForEditing.scrolling.reverse.vertical ?? false
    }

    private var reverseHorizontalValue: Bool {
        selectedScheme?.scrolling.reverse.horizontal ?? effectiveSchemeForEditing.scrolling.reverse.horizontal ?? false
    }

    private var universalBackForwardChoice: RulesPrototypeUniversalBackForwardChoice {
        RulesPrototypeUniversalBackForwardChoice(selectedScheme?.buttons
            .universalBackForward ?? effectiveSchemeForEditing.buttons.universalBackForward ?? .none)
    }

    private var switchPrimaryValue: Bool {
        selectedScheme?.buttons.switchPrimaryButtonAndSecondaryButtons ?? effectiveSchemeForEditing.buttons
            .switchPrimaryButtonAndSecondaryButtons ?? false
    }

    private var scrollModeValue: RulesPrototypeScrollMode {
        if let selectedScheme, RulesPrototypeSettingKey.scrollMode.isSet(in: selectedScheme) {
            return RulesPrototypePresenter.scrollMode(for: selectedScheme)
        }
        return RulesPrototypePresenter.scrollMode(for: effectiveSchemeForEditing)
    }

    private var linearScrollUnitValue: RulesPrototypeLinearScrollUnit {
        switch selectedScheme?.scrolling.distance.vertical ?? selectedScheme?.scrolling.distance
            .horizontal ?? effectiveSchemeForEditing.scrolling.distance.vertical ?? effectiveSchemeForEditing.scrolling
            .distance.horizontal {
        case .some(.pixel):
            return .pixels
        case .some(.line), .some(.auto), nil:
            return .lines
        }
    }

    private var verticalDistanceValue: Int {
        RulesPrototypePresenter.lineDistanceValue(
            selectedScheme?.scrolling.distance.vertical ?? effectiveSchemeForEditing.scrolling.distance.vertical,
            fallback: 3
        )
    }

    private var horizontalDistanceValue: Int {
        RulesPrototypePresenter.lineDistanceValue(
            selectedScheme?.scrolling.distance.horizontal ?? effectiveSchemeForEditing.scrolling.distance.horizontal,
            fallback: verticalDistanceValue
        )
    }

    private var verticalPixelDistanceValue: Double {
        RulesPrototypePresenter.pixelDistance(
            selectedScheme?.scrolling.distance.vertical ?? effectiveSchemeForEditing.scrolling.distance.vertical,
            fallback: 36
        )
    }

    private var horizontalPixelDistanceValue: Double {
        RulesPrototypePresenter.pixelDistance(
            selectedScheme?.scrolling.distance.horizontal ?? effectiveSchemeForEditing.scrolling.distance.horizontal,
            fallback: verticalPixelDistanceValue
        )
    }

    private var verticalScrollAccelerationValue: Double {
        (selectedScheme?.scrolling.acceleration.vertical ?? effectiveSchemeForEditing.scrolling.acceleration.vertical)?
            .asTruncatedDouble ?? 1
    }

    private var horizontalScrollAccelerationValue: Double {
        (selectedScheme?.scrolling.acceleration.horizontal ?? effectiveSchemeForEditing.scrolling.acceleration
            .horizontal)?.asTruncatedDouble ?? verticalScrollAccelerationValue
    }

    private var verticalScrollSpeedValue: Double {
        (selectedScheme?.scrolling.speed.vertical ?? effectiveSchemeForEditing.scrolling.speed.vertical)?
            .asTruncatedDouble ?? 0
    }

    private var horizontalScrollSpeedValue: Double {
        (selectedScheme?.scrolling.speed.horizontal ?? effectiveSchemeForEditing.scrolling.speed.horizontal)?
            .asTruncatedDouble ?? verticalScrollSpeedValue
    }

    private var smoothedPresetValue: Scheme.Scrolling.Smoothed.Preset {
        selectedScheme?.scrolling.smoothed.vertical?.preset
            ?? effectiveSchemeForEditing.scrolling.smoothed.vertical?.preset
            ?? .defaultPreset
    }

    private var smoothedResponseValue: Double {
        selectedScheme?.scrolling.smoothed.vertical?.response?.asTruncatedDouble
            ?? effectiveSchemeForEditing.scrolling.smoothed.vertical?.response?.asTruncatedDouble
            ?? 0.68
    }

    private var smoothedSpeedValue: Double {
        selectedScheme?.scrolling.smoothed.vertical?.speed?.asTruncatedDouble
            ?? effectiveSchemeForEditing.scrolling.smoothed.vertical?.speed?.asTruncatedDouble
            ?? 1
    }

    private var smoothedAccelerationValue: Double {
        selectedScheme?.scrolling.smoothed.vertical?.acceleration?.asTruncatedDouble
            ?? effectiveSchemeForEditing.scrolling.smoothed.vertical?.acceleration?.asTruncatedDouble
            ?? 1
    }

    private var smoothedInertiaValue: Double {
        selectedScheme?.scrolling.smoothed.vertical?.inertia?.asTruncatedDouble
            ?? effectiveSchemeForEditing.scrolling.smoothed.vertical?.inertia?.asTruncatedDouble
            ?? 1
    }

    private var smoothedBouncingValue: Bool {
        selectedScheme?.scrolling.smoothed.vertical?.bouncing
            ?? effectiveSchemeForEditing.scrolling.smoothed.vertical?.bouncing
            ?? true
    }

    private var autoScrollValue: Bool {
        selectedScheme?.buttons.autoScroll.enabled ?? effectiveSchemeForEditing.buttons.autoScroll.enabled ?? false
    }

    private var autoScrollTriggerValue: Scheme.Buttons.Mapping {
        selectedScheme?.buttons.autoScroll.trigger
            ?? effectiveSchemeForEditing.buttons.autoScroll.trigger
            ?? RulesPrototypePresenter.defaultTriggerMapping()
    }

    private var autoScrollModesValue: [Scheme.Buttons.AutoScroll.Mode] {
        selectedScheme?.buttons.autoScroll.normalizedModes
            ?? effectiveSchemeForEditing.buttons.autoScroll.normalizedModes
    }

    private var autoScrollSpeedValue: Double {
        (selectedScheme?.buttons.autoScroll.speed ?? effectiveSchemeForEditing.buttons.autoScroll.speed)?
            .asTruncatedDouble ?? 1
    }

    private var autoScrollPreserveNativeMiddleClickValue: Bool {
        selectedScheme?.buttons.autoScroll.preserveNativeMiddleClick
            ?? effectiveSchemeForEditing.buttons.autoScroll.preserveNativeMiddleClick
            ?? true
    }

    private var gestureValue: Bool {
        selectedScheme?.buttons.gesture.enabled ?? effectiveSchemeForEditing.buttons.gesture.enabled ?? false
    }

    private var gestureTriggerValue: Scheme.Buttons.Mapping {
        selectedScheme?.buttons.gesture.trigger
            ?? effectiveSchemeForEditing.buttons.gesture.trigger
            ?? RulesPrototypePresenter.defaultTriggerMapping()
    }

    private var gestureThresholdValue: Int {
        selectedScheme?.buttons.gesture.threshold ?? effectiveSchemeForEditing.buttons.gesture.threshold ?? 50
    }

    private var clickDebouncingTimeoutValue: Int {
        selectedScheme?.buttons.clickDebouncing.timeout ?? effectiveSchemeForEditing.buttons.clickDebouncing
            .timeout ?? 50
    }

    private var clickDebouncingResetTimerOnMouseUpValue: Bool {
        selectedScheme?.buttons.clickDebouncing.resetTimerOnMouseUp
            ?? effectiveSchemeForEditing.buttons.clickDebouncing.resetTimerOnMouseUp
            ?? false
    }

    private var clickDebouncingButtonsValue: [CGMouseButton] {
        selectedScheme?.buttons.clickDebouncing.buttons
            ?? effectiveSchemeForEditing.buttons.clickDebouncing.buttons
            ?? [.left, .right, .center, .back, .forward]
    }

    private func gestureActionValue(
        _ keyPath: WritableKeyPath<Scheme.Buttons.Gesture.Actions, Scheme.Buttons.Gesture.GestureAction?>,
        fallback: Scheme.Buttons.Gesture.GestureAction
    ) -> Scheme.Buttons.Gesture.GestureAction {
        selectedScheme?.buttons.gesture.actions[keyPath: keyPath]
            ?? effectiveSchemeForEditing.buttons.gesture.actions[keyPath: keyPath]
            ?? fallback
    }

    private func modifierAction(
        direction: Scheme.Scrolling.BidirectionalDirection,
        keyPath: WritableKeyPath<Scheme.Scrolling.Modifiers, Scheme.Scrolling.Modifiers.Action?>
    ) -> Scheme.Scrolling.Modifiers.Action? {
        selectedScheme?.scrolling.modifiers[direction]?[keyPath: keyPath]
    }

    private func updateSelectedRule(
        _ actionName: String = NSLocalizedString("Change Setting", comment: ""),
        _ update: (inout Scheme) -> Void
    ) {
        guard schemes.indices.contains(selectedRuleIndex) else {
            return
        }

        withConfigurationUndo(actionName) {
            var configuration = configurationState.configuration
            update(&configuration.schemes[selectedRuleIndex])
            configuration.schemes[selectedRuleIndex].removeEmptyPrototypeSections()
            configurationState.configuration = configuration
        }
    }

    private func withConfigurationUndo(_ actionName: String, _ change: () -> Void) {
        undoTarget.configurationState = configurationState
        undoTarget.undoManager = view.window?.undoManager

        let before = configurationState.configuration
        change()
        guard configurationState.configuration != before else {
            return
        }

        view.window?.undoManager?.registerUndo(withTarget: undoTarget) { target in
            target.restore(before, actionName: actionName)
        }
        view.window?.undoManager?.setActionName(actionName)
    }

    private func normalizeSelection() {
        guard !schemes.isEmpty else {
            selectedRuleIndex = 0
            return
        }
        selectedRuleIndex = min(max(selectedRuleIndex, 0), schemes.count - 1)
    }

    private func ensureVisibleDefaultRule() {
        if selectVisibleRuleIfNeeded() {
            return
        }

        guard !schemes.contains(where: RulesPrototypeFoundationRuleKind.allMice.matches) else {
            return
        }

        var scheme = RulesPrototypeFoundationRuleKind.allMice.makeScheme(
            mouseMatcher: mouseCategoryMatcher(),
            trackpadMatcher: trackpadCategoryMatcher()
        )
        scheme.removeEmptyPrototypeSections()
        var configuration = configurationState.configuration
        configuration.schemes.insert(scheme, at: foundationInsertionIndex(for: .allMice))
        configurationState.configuration = configuration
        selectedRuleIndex = configuration.schemes
            .firstIndex(where: RulesPrototypeFoundationRuleKind.allMice.matches) ?? 0
    }

    @discardableResult
    private func selectVisibleRuleIfNeeded() -> Bool {
        guard let selectedScheme else {
            return false
        }

        guard RulesPrototypeFoundationRuleKind.kind(for: selectedScheme) == .global else {
            return true
        }

        if let allMiceIndex = schemes.firstIndex(where: RulesPrototypeFoundationRuleKind.allMice.matches) {
            selectedRuleIndex = allMiceIndex
            return true
        }

        if let visibleIndex = schemes.indices.first(where: { index in
            RulesPrototypeFoundationRuleKind.kind(for: schemes[index]) != .global
        }) {
            selectedRuleIndex = visibleIndex
            return true
        }

        return false
    }

    @objc private func ruleNameCommitted(_ sender: NSTextField) {
        guard RulesPrototypeFoundationRuleKind.kind(for: selectedScheme ?? Scheme()) == nil else {
            return
        }
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSelectedRule(NSLocalizedString("Rename Rule", comment: "")) {
            $0.name = trimmed.isEmpty ? nil : sender.stringValue
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }
        let identifier = field.identifier?.rawValue
        if field === titleField {
            ruleNameCommitted(field)
        } else if identifier?.hasPrefix("mapping.run.") == true {
            mappingRunCommandCommitted(field)
        } else if identifier == "clickDebouncing.timeout" ||
            identifier == "gesture.threshold" ||
            identifier?.hasSuffix(".lines") == true {
            integerFieldCommitted(field)
        } else {
            decimalFieldCommitted(field)
        }
    }

    @objc private func unsetSetting(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let key = RulesPrototypeSettingKey(rawValue: rawValue) else {
            return
        }
        updateSelectedRule(NSLocalizedString("Use Earlier Value", comment: "")) {
            key.unset(in: &$0)
        }
    }

    @objc private func unsetSettingsSection(_ sender: NSButton) {
        guard let section = selectedSection(), sender.identifier?.rawValue == section.id else {
            return
        }
        updateSelectedRule(NSLocalizedString("Use Earlier Values", comment: "")) { scheme in
            for key in section.keys {
                key.unset(in: &scheme)
            }
        }
    }

    @objc private func checkboxChanged(_ sender: NSControl) {
        let enabled = sender.intValue != 0
        guard let identifier = sender.identifier?.rawValue else {
            return
        }

        let requiresEventTapRestart = identifier == RulesPrototypeSettingKey.redirectsToScroll.rawValue ||
            identifier == "autoScroll.enabled" ||
            identifier == "gesture.enabled"

        updateSelectedRule {
            switch identifier {
            case RulesPrototypeSettingKey.redirectsToScroll.rawValue:
                $0.pointer.redirectsToScroll = enabled
            case RulesPrototypeSettingKey.reverseVertical.rawValue:
                $0.scrolling.reverse.vertical = enabled
            case RulesPrototypeSettingKey.reverseHorizontal.rawValue:
                $0.scrolling.reverse.horizontal = enabled
            case RulesPrototypeSettingKey.switchPrimary.rawValue:
                $0.buttons.switchPrimaryButtonAndSecondaryButtons = enabled
            case "pointerAcceleration.disabled":
                $0.pointer.disableAcceleration = enabled
            case "scroll.smoothed.bouncing":
                RulesPrototypePresenter.updateVerticalSmoothed(in: &$0) { $0.bouncing = enabled }
            case "autoScroll.enabled":
                $0.buttons.autoScroll.enabled = enabled
                if enabled {
                    configureAutoScrollDefaults(in: &$0)
                }
            case "autoScroll.mode.toggle":
                setAutoScrollMode(.toggle, enabled: enabled, in: &$0)
            case "autoScroll.mode.hold":
                setAutoScrollMode(.hold, enabled: enabled, in: &$0)
            case "autoScroll.preserveNativeMiddleClick":
                $0.buttons.autoScroll.preserveNativeMiddleClick = enabled
            case "gesture.enabled":
                $0.buttons.gesture.enabled = enabled
                if enabled {
                    configureGestureDefaults(in: &$0)
                }
            case "clickDebouncing.resetOnMouseUp":
                $0.buttons.clickDebouncing.resetTimerOnMouseUp = enabled
            default:
                if identifier.hasPrefix("mapping.repeat.") {
                    let index = Int(identifier.replacingOccurrences(of: "mapping.repeat.", with: "")) ?? -1
                    setMappingRepeat(enabled, index: index, in: &$0)
                } else if identifier.hasPrefix("clickDebouncing.button."),
                          let rawButton = UInt32(identifier.replacingOccurrences(
                              of: "clickDebouncing.button.",
                              with: ""
                          )),
                          let button = CGMouseButton(rawValue: rawButton) {
                    var buttons = clickDebouncingButtonsValue
                    if enabled, !buttons.contains(button) {
                        buttons.append(button)
                    } else if !enabled {
                        buttons.removeAll { $0 == button }
                    }
                    $0.buttons.clickDebouncing.buttons = buttons
                }
            }
        }

        if requiresEventTapRestart {
            restartEventTap()
        }
    }

    @objc private func segmentedChanged(_ sender: NSSegmentedControl) {
        guard sender.identifier?.rawValue == "scrollMode",
              RulesPrototypeScrollMode.allCases.indices.contains(sender.selectedSegment) else {
            return
        }
        let mode = RulesPrototypeScrollMode.allCases[sender.selectedSegment]
        let inherited = effectiveSchemeForEditing
        updateSelectedRule(NSLocalizedString("Change Scrolling Mode", comment: "")) {
            RulesPrototypePresenter.applyScrollMode(mode, to: &$0, inherited: inherited)
        }
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let identifier = sender.identifier?.rawValue else {
            return
        }

        updateSelectedRule {
            switch identifier {
            case RulesPrototypeSettingKey.universalBackForward.rawValue:
                if let rawValue = sender.selectedItem?.representedObject as? String,
                   let choice = RulesPrototypeUniversalBackForwardChoice(rawValue: rawValue) {
                    $0.buttons.universalBackForward = choice.value
                }
            case "scroll.linearUnit":
                if let rawValue = sender.selectedItem?.representedObject as? String,
                   let unit = RulesPrototypeLinearScrollUnit(rawValue: rawValue) {
                    applyLinearScrollUnit(unit, to: &$0)
                }
            case "scroll.smoothed.preset":
                if let rawValue = sender.selectedItem?.representedObject as? String,
                   let preset = Scheme.Scrolling.Smoothed.Preset(rawValue: rawValue) {
                    var configuration = preset.defaultConfiguration
                    configuration.bouncing = smoothedBouncingValue
                    $0.scrolling.smoothed.vertical = configuration
                    $0.scrolling.smoothed.horizontal = configuration
                }
            default:
                if identifier.hasPrefix("mapping.action.") {
                    let index = Int(identifier.replacingOccurrences(of: "mapping.action.", with: "")) ?? -1
                    setMappingAction(
                        sender.selectedItem?.representedObject as? RulesPrototypeMappingActionChoice,
                        index: index,
                        in: &$0
                    )
                } else if identifier.hasPrefix("mapping.keyBehavior.") {
                    let index = Int(identifier.replacingOccurrences(of: "mapping.keyBehavior.", with: "")) ?? -1
                    setMappingKeyPressBehavior(sender.selectedItem?.representedObject as? String, index: index, in: &$0)
                } else if identifier.hasPrefix("gesture.action.") {
                    setGestureAction(sender.selectedItem?.representedObject as? String, identifier: identifier, in: &$0)
                } else if identifier.hasPrefix("modifier.") {
                    setModifierAction(sender.selectedItem?.representedObject as? Int, tag: sender.tag, in: &$0)
                }
            }
        }
    }

    @objc private func decimalSliderChanged(_ sender: NSSlider) {
        applyDecimalValue(sender.doubleValue, identifier: sender.identifier?.rawValue)
    }

    @objc private func decimalFieldCommitted(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue) else {
            renderAll()
            return
        }
        applyDecimalValue(value, identifier: sender.identifier?.rawValue)
    }

    private func applyDecimalValue(_ value: Double, identifier: String?) {
        guard let identifier else {
            return
        }
        updateSelectedRule {
            let decimal = Decimal(value).rounded(4)
            switch identifier {
            case RulesPrototypeSettingKey.pointerSpeed.rawValue:
                $0.pointer.speed = .value(decimal)
            case RulesPrototypeSettingKey.pointerAcceleration.rawValue:
                $0.pointer.acceleration = .value(decimal)
            case "scroll.acceleration.vertical":
                $0.scrolling.acceleration.vertical = decimal
            case "scroll.acceleration.horizontal":
                $0.scrolling.acceleration.horizontal = decimal
            case "scroll.speed.vertical":
                $0.scrolling.speed.vertical = decimal
            case "scroll.speed.horizontal":
                $0.scrolling.speed.horizontal = decimal
            case "scroll.distance.vertical.pixels":
                $0.scrolling.distance.vertical = .pixel(decimal.rounded(1))
            case "scroll.distance.horizontal.pixels":
                $0.scrolling.distance.horizontal = .pixel(decimal.rounded(1))
            case "scroll.smoothed.response":
                RulesPrototypePresenter.updateVerticalSmoothed(in: &$0) { $0.response = decimal }
            case "scroll.smoothed.speed":
                RulesPrototypePresenter.updateVerticalSmoothed(in: &$0) { $0.speed = decimal }
            case "scroll.smoothed.acceleration":
                RulesPrototypePresenter.updateVerticalSmoothed(in: &$0) { $0.acceleration = decimal }
            case "scroll.smoothed.inertia":
                RulesPrototypePresenter.updateVerticalSmoothed(in: &$0) { $0.inertia = decimal }
            case "autoScroll.speed":
                $0.buttons.autoScroll.speed = decimal
            default:
                break
            }
        }
    }

    @objc private func integerStepperChanged(_ sender: NSStepper) {
        applyIntegerValue(Int(sender.integerValue), identifier: sender.identifier?.rawValue)
    }

    @objc private func integerFieldCommitted(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue) else {
            renderAll()
            return
        }
        applyIntegerValue(value, identifier: sender.identifier?.rawValue)
    }

    private func applyIntegerValue(_ value: Int, identifier: String?) {
        guard let identifier else {
            return
        }
        updateSelectedRule {
            switch identifier {
            case "scroll.distance.vertical.lines":
                $0.scrolling.distance.vertical = .line(value)
            case "scroll.distance.horizontal.lines":
                $0.scrolling.distance.horizontal = .line(value)
            case "gesture.threshold":
                $0.buttons.gesture.threshold = value
            case "clickDebouncing.timeout":
                $0.buttons.clickDebouncing.timeout = value
            default:
                break
            }
        }
    }

    private func applyLinearScrollUnit(_ unit: RulesPrototypeLinearScrollUnit, to scheme: inout Scheme) {
        let inherited = effectiveSchemeForEditing
        switch unit {
        case .lines:
            scheme.scrolling.distance.vertical = .line(
                RulesPrototypePresenter.lineDistance(
                    scheme.scrolling.distance.vertical ?? inherited.scrolling.distance.vertical,
                    fallback: 3
                )
            )
            scheme.scrolling.distance.horizontal = .line(
                RulesPrototypePresenter.lineDistance(
                    scheme.scrolling.distance.horizontal ?? inherited.scrolling.distance.horizontal ?? inherited
                        .scrolling.distance.vertical,
                    fallback: 3
                )
            )
        case .pixels:
            scheme.scrolling.distance.vertical = .pixel(Decimal(
                RulesPrototypePresenter.pixelDistance(
                    scheme.scrolling.distance.vertical ?? inherited.scrolling.distance.vertical,
                    fallback: 36
                )
            ).rounded(1))
            scheme.scrolling.distance.horizontal = .pixel(Decimal(
                RulesPrototypePresenter.pixelDistance(
                    scheme.scrolling.distance.horizontal ?? inherited.scrolling.distance.horizontal ?? inherited
                        .scrolling.distance.vertical,
                    fallback: 36
                )
            ).rounded(1))
        }
    }

    private func setAutoScrollMode(_ mode: Scheme.Buttons.AutoScroll.Mode, enabled: Bool, in scheme: inout Scheme) {
        var modes = scheme.buttons.autoScroll.normalizedModes
        if enabled, !modes.contains(mode) {
            modes.append(mode)
        } else if !enabled {
            modes.removeAll { $0 == mode }
        }
        scheme.buttons.autoScroll.modes = modes.isEmpty ? [.toggle] : RulesPrototypePresenter
            .orderedAutoScrollModes(modes)
    }

    private func configureAutoScrollDefaults(in scheme: inout Scheme) {
        if scheme.buttons.autoScroll.trigger == nil {
            scheme.buttons.autoScroll.trigger = RulesPrototypePresenter.defaultTriggerMapping()
        }
        if scheme.buttons.autoScroll.modes == nil {
            scheme.buttons.autoScroll.modes = [.toggle]
        }
        if scheme.buttons.autoScroll.speed == nil {
            scheme.buttons.autoScroll.speed = 1
        }
        if scheme.buttons.autoScroll.preserveNativeMiddleClick == nil {
            scheme.buttons.autoScroll.preserveNativeMiddleClick = true
        }
    }

    private func configureGestureDefaults(in scheme: inout Scheme) {
        if scheme.buttons.gesture.trigger == nil {
            scheme.buttons.gesture.trigger = RulesPrototypePresenter.defaultTriggerMapping()
        }
        if scheme.buttons.gesture.threshold == nil {
            scheme.buttons.gesture.threshold = 50
        }
        if scheme.buttons.gesture.actions.left == nil {
            scheme.buttons.gesture.actions.left = .spaceLeft
        }
        if scheme.buttons.gesture.actions.right == nil {
            scheme.buttons.gesture.actions.right = .spaceRight
        }
        if scheme.buttons.gesture.actions.up == nil {
            scheme.buttons.gesture.actions.up = .missionControl
        }
        if scheme.buttons.gesture.actions.down == nil {
            scheme.buttons.gesture.actions.down = .appExpose
        }
    }

    private func setMappingAction(_ choice: RulesPrototypeMappingActionChoice?, index: Int, in scheme: inout Scheme) {
        guard index >= 0 else {
            return
        }
        var mappings = scheme.buttons.mappings ?? selectedScheme?.buttons.mappings ?? []
        guard mappings.indices.contains(index) else {
            return
        }
        if let choice {
            mappings[index].action = choice.action(preserving: mappings[index].action)
        }
        scheme.buttons.mappings = mappings
    }

    private func setMappingKeyPressBehavior(_ rawValue: String?, index: Int, in scheme: inout Scheme) {
        guard index >= 0,
              let rawValue,
              let behavior = Scheme.Buttons.Mapping.KeyPressBehavior(rawValue: rawValue) else {
            return
        }
        var mappings = scheme.buttons.mappings ?? selectedScheme?.buttons.mappings ?? []
        guard mappings.indices.contains(index) else {
            return
        }
        mappings[index].keyPressBehavior = behavior
        scheme.buttons.mappings = mappings
    }

    private func setMappingRepeat(_ enabled: Bool, index: Int, in scheme: inout Scheme) {
        guard index >= 0 else {
            return
        }
        var mappings = scheme.buttons.mappings ?? selectedScheme?.buttons.mappings ?? []
        guard mappings.indices.contains(index) else {
            return
        }
        mappings[index].repeat = enabled ? true : nil
        if enabled {
            mappings[index].hold = nil
        }
        scheme.buttons.mappings = mappings
    }

    @objc private func mappingRunCommandCommitted(_ sender: NSTextField) {
        let index = Int(sender.identifier?.rawValue.replacingOccurrences(of: "mapping.run.", with: "") ?? "") ?? -1
        updateSelectedRule(NSLocalizedString("Change Mapping Command", comment: "")) {
            var mappings = $0.buttons.mappings ?? selectedScheme?.buttons.mappings ?? []
            guard mappings.indices.contains(index) else {
                return
            }
            mappings[index].action = .arg1(.run(sender.stringValue))
            $0.buttons.mappings = mappings
        }
    }

    private func setGestureAction(_ rawValue: String?, identifier: String, in scheme: inout Scheme) {
        guard let rawValue, let action = Scheme.Buttons.Gesture.GestureAction(rawValue: rawValue) else {
            return
        }
        switch identifier {
        case "gesture.action.left":
            scheme.buttons.gesture.actions.left = action
        case "gesture.action.right":
            scheme.buttons.gesture.actions.right = action
        case "gesture.action.up":
            scheme.buttons.gesture.actions.up = action
        case "gesture.action.down":
            scheme.buttons.gesture.actions.down = action
        default:
            break
        }
    }

    private func setModifierAction(_ rawValue: Int?, tag: Int, in scheme: inout Scheme) {
        guard let field = RulesPrototypeModifierField(tag: tag),
              let rawValue,
              let choice = RulesPrototypeModifierChoice(rawValue: rawValue) else {
            return
        }

        var modifiers = scheme.scrolling.modifiers
        if modifiers[field.direction] == nil {
            modifiers[field.direction] = Scheme.Scrolling.Modifiers()
        }
        let action = choice.action
        switch field.modifier {
        case .command:
            modifiers[field.direction]?.command = action
        case .shift:
            modifiers[field.direction]?.shift = action
        case .option:
            modifiers[field.direction]?.option = action
        case .control:
            modifiers[field.direction]?.control = action
        }
        scheme.scrolling.modifiers = modifiers
    }

    @objc private func addButtonMapping() {
        updateSelectedRule(NSLocalizedString("Add Button Mapping", comment: "")) {
            $0.buttons.mappings = ($0.buttons.mappings ?? []) + [RulesPrototypePresenter.blankMapping()]
        }
    }

    @objc private func removeButtonMapping(_ sender: NSButton) {
        updateSelectedRule(NSLocalizedString("Remove Button Mapping", comment: "")) {
            var mappings = $0.buttons.mappings ?? []
            guard mappings.indices.contains(sender.tag) else {
                return
            }
            mappings.remove(at: sender.tag)
            $0.buttons.mappings = mappings.isEmpty ? nil : mappings
        }
    }

    @objc private func recordMappingButton(_ sender: NSButton) {
        startRecording(.mapping(index: sender.tag), button: sender)
    }

    @objc private func recordMappingKeyPress(_ sender: NSButton) {
        startKeyRecording(index: sender.tag, button: sender)
    }

    @objc private func recordAutoScrollTrigger(_ sender: NSButton) {
        startRecording(.autoScrollTrigger, button: sender)
    }

    @objc private func recordGestureTrigger(_ sender: NSButton) {
        startRecording(.gestureTrigger, button: sender)
    }

    private func startRecording(_ target: RulesPrototypeRecordingTarget, button: NSButton) {
        stopRecording()
        recordingTarget = target
        recordingButton = button

        beginVirtualButtonRecording()
        button.title = recordingPromptTitle()
        settingsState.recordedVirtualButtonEvent = nil
        recordedButtonCancellable = settingsState
            .$recordedVirtualButtonEvent
            .compactMap(\.self)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.recordVirtualButton(event)
            }

        recordingObservationToken = try? EventTap.observe([
            .flagsChanged,
            .scrollWheel,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ], place: .tailAppendEventTap) { [weak self] _, event in
            self?.record(event)
        }

        if recordingObservationToken == nil {
            button.title = NSLocalizedString("Recording unavailable", comment: "")
            stopRecording(resetButton: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak button] in
                guard self?.recordingButton == nil else {
                    return
                }
                button?.title = self?.titleForRecordingButton(target) ?? NSLocalizedString("Record Button", comment: "")
            }
        }
    }

    private func stopRecording(resetButton: Bool = true) {
        recordingObservationToken?.cancel()
        recordingObservationToken = nil
        recordedButtonCancellable?.cancel()
        recordedButtonCancellable = nil
        endVirtualButtonRecording()
        if resetButton, let recordingButton, let recordingTarget {
            recordingButton.title = titleForRecordingButton(recordingTarget)
        }
        recordingTarget = nil
        recordingButton = nil
    }

    private func beginVirtualButtonRecording() {
        let monitorDevices = logitechMonitorDevices()
        settingsState.beginVirtualButtonRecordingPreparation(for: Set(monitorDevices.map(\.id)))
        settingsState.recording = true
        monitorDevices.forEach { $0.prepareLogitechControlsRecording() }
    }

    private func endVirtualButtonRecording() {
        settingsState.endVirtualButtonRecordingPreparation()
        settingsState.recording = false
        settingsState.recordedVirtualButtonEvent = nil
    }

    private func logitechMonitorDevices() -> [Device] {
        guard let currentDevice = DeviceState.shared.currentDeviceRef?.value,
              currentDevice.hasLogitechControlsMonitor else {
            return []
        }
        return [currentDevice]
    }

    private func recordingPromptTitle() -> String {
        NSLocalizedString("Recording", comment: "")
    }

    private func titleForRecordingButton(_ target: RulesPrototypeRecordingTarget) -> String {
        switch target {
        case let .mapping(index):
            let mappings = selectedScheme?.buttons.mappings ?? []
            if mappings.indices.contains(index) {
                return RulesPrototypePresenter.mappingTargetTitle(mappings[index])
            }
            return NSLocalizedString("Record Button", comment: "")
        case .autoScrollTrigger:
            return RulesPrototypePresenter.mappingTargetTitle(autoScrollTriggerValue)
        case .gestureTrigger:
            return RulesPrototypePresenter.mappingTargetTitle(gestureTriggerValue)
        }
    }

    private func record(_ event: CGEvent) -> CGEvent? {
        guard let target = recordingTarget,
              let mapping = RulesPrototypePresenter.mapping(from: event) else {
            return nil
        }

        if event.type == .flagsChanged {
            return nil
        }

        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            if !mapping.valid {
                showInvalidRecordingFeedback(message: invalidRecordingMessage(for: mapping), target: target)
            } else {
                recordingButton?.title = RulesPrototypePresenter.mappingTargetTitle(mapping)
            }
            return nil
        }

        record(mapping, target: target)
        return nil
    }

    private func recordVirtualButton(_ event: SettingsState.RecordedVirtualButtonEvent) {
        guard let target = recordingTarget else {
            return
        }
        var mapping = Scheme.Buttons.Mapping()
        mapping.button = event.button
        mapping.modifierFlags = event.modifierFlags
        record(mapping, target: target)
    }

    private func record(_ mapping: Scheme.Buttons.Mapping, target: RulesPrototypeRecordingTarget) {
        let mappingToStore: Scheme.Buttons.Mapping
        switch target {
        case .mapping:
            mappingToStore = mapping
        case .autoScrollTrigger, .gestureTrigger:
            mappingToStore = RulesPrototypePresenter.sanitizedTrigger(mapping)
        }

        guard mappingToStore.valid else {
            showInvalidRecordingFeedback(message: invalidRecordingMessage(for: mapping), target: target)
            return
        }

        var mapping = mappingToStore
        updateSelectedRule(NSLocalizedString("Record Button", comment: "")) {
            switch target {
            case let .mapping(index):
                var mappings = $0.buttons.mappings ?? selectedScheme?.buttons.mappings ?? []
                while mappings.count <= index {
                    mappings.append(RulesPrototypePresenter.blankMapping())
                }
                let action = mappings[index].action
                mapping.action = action
                mappings[index] = mapping
                $0.buttons.mappings = mappings
            case .autoScrollTrigger:
                $0.buttons.autoScroll.trigger = mapping
            case .gestureTrigger:
                $0.buttons.gesture.trigger = mapping
            }
        }

        stopRecording()
    }

    private func invalidRecordingMessage(for mapping: Scheme.Buttons.Mapping) -> String {
        if mapping.button?.mouseButtonNumber == Int(CGMouseButton.left.rawValue), mapping.modifierFlags.isEmpty {
            return NSLocalizedString("Primary click needs a modifier", comment: "")
        }
        return NSLocalizedString("Choose a mouse button trigger", comment: "")
    }

    private func showInvalidRecordingFeedback(message: String, target: RulesPrototypeRecordingTarget) {
        recordingButton?.title = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.recordingTarget == target else {
                return
            }
            self.recordingButton?.title = self.recordingPromptTitle()
        }
    }

    private func startKeyRecording(index: Int, button: NSButton) {
        stopKeyRecording()
        keyRecordingIndex = index
        keyRecordingButton = button
        keyRecordingModifiers = []
        button.title = NSLocalizedString("Recording", comment: "")

        keyRecordingObservationToken = try? EventTap.observe([
            .flagsChanged,
            .keyDown
        ]) { [weak self] _, event in
            self?.recordKeyPress(event)
        }

        if keyRecordingObservationToken == nil {
            button.title = NSLocalizedString("Recording unavailable", comment: "")
            stopKeyRecording(resetButton: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak button] in
                button?.title = self?.keyPressTitleForMapping(at: index) ?? NSLocalizedString(
                    "Click to record",
                    comment: ""
                )
            }
        }
    }

    private func stopKeyRecording(resetButton: Bool = true) {
        keyRecordingObservationToken?.cancel()
        keyRecordingObservationToken = nil
        if resetButton, let keyRecordingButton, let keyRecordingIndex {
            keyRecordingButton.title = keyPressTitleForMapping(at: keyRecordingIndex)
        }
        keyRecordingIndex = nil
        keyRecordingButton = nil
        keyRecordingModifiers = []
    }

    private func keyPressTitleForMapping(at index: Int) -> String {
        let mappings = selectedScheme?.buttons.mappings ?? []
        guard mappings.indices.contains(index),
              case let .arg1(.keyPress(keys)) = mappings[index].action else {
            return NSLocalizedString("Click to record", comment: "")
        }
        return RulesPrototypePresenter.keyPressTitle(keys)
    }

    private func recordKeyPress(_ event: CGEvent) -> CGEvent? {
        guard let keyRecordingIndex else {
            return nil
        }

        switch event.type {
        case .flagsChanged:
            keyRecordingModifiers.insert(event.flags)
            if event.flags.isDisjoint(with: [.maskControl, .maskShift, .maskAlternate, .maskCommand]) {
                setKeyPressKeys(RulesPrototypePresenter.keys(from: keyRecordingModifiers), index: keyRecordingIndex)
                stopKeyRecording()
            }

        case .keyDown:
            let resolver = KeyCodeResolver()
            guard let key = resolver.key(from: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))) else {
                return nil
            }
            setKeyPressKeys(RulesPrototypePresenter.keys(from: event.flags) + [key], index: keyRecordingIndex)
            stopKeyRecording()

        default:
            break
        }

        return nil
    }

    private func setKeyPressKeys(_ keys: [Key], index: Int) {
        updateSelectedRule(NSLocalizedString("Record Keyboard Shortcut", comment: "")) {
            var mappings = $0.buttons.mappings ?? selectedScheme?.buttons.mappings ?? []
            guard mappings.indices.contains(index) else {
                return
            }
            mappings[index].action = .arg1(.keyPress(keys))
            $0.buttons.mappings = mappings
        }
    }

    @objc private func showRulePopover(_ sender: NSView?) {
        guard let sender else {
            return
        }
        if rulePopover?.isShown == true {
            rulePopover?.close()
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        let pickerRows = RulesPrototypeFoundationRuleKind.visibleCases.count + max(customRuleIndices.count, 1)
        let pickerHeight = min(CGFloat(560), CGFloat(144 + pickerRows * 48))
        popover.contentSize = NSSize(width: 320, height: pickerHeight)
        let controller = NSViewController()
        controller.view = makeRulePickerPopover()
        popover.contentViewController = controller
        rulePopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }

    private func makeRulePickerPopover() -> NSView {
        let root = rpVerticalStack(spacing: 12)
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let header = rpHorizontalStack(spacing: 8)
        header.addArrangedSubview(rpLabel(NSLocalizedString("Rules", comment: ""), size: 15, weight: .semibold))
        header.addArrangedSubview(rpFlexibleSpace())
        let manageIcon = NSButton(
            image: rpSymbolImage("slider.horizontal.3") ?? NSImage(),
            target: self,
            action: #selector(showRuleManagerFromPopover)
        )
        manageIcon.isBordered = false
        manageIcon.toolTip = NSLocalizedString("Manage Rules", comment: "")
        header.addArrangedSubview(manageIcon)
        root.addArrangedSubview(header)

        root.addArrangedSubview(makeRulePickerSection(
            title: NSLocalizedString("Defaults", comment: ""),
            rows: RulesPrototypeFoundationRuleKind.visibleCases.map { kind in
                RulesPrototypeRulePickerRowModel(
                    title: kind.title,
                    subtitle: kind.subtitle,
                    symbol: kind.symbol,
                    selected: selectedScheme.map(kind.matches) == true
                ) { [weak self] in
                    self?.selectOrCreateFoundationRule(kind)
                    self?.rulePopover?.close()
                }
            }
        ))

        let customRows = customRuleIndices.map { index in
            RulesPrototypeRulePickerRowModel(
                title: RulesPrototypePresenter.title(for: schemes[index], at: index),
                subtitle: RulesPrototypePresenter.targetSummary(for: schemes[index]),
                symbol: RulesPrototypePresenter.symbol(for: schemes[index]),
                selected: selectedRuleIndex == index
            ) { [weak self] in
                self?.selectedRuleIndex = index
                self?.rulePopover?.close()
                self?.renderAll()
            }
        }
        root.addArrangedSubview(makeRulePickerSection(
            title: NSLocalizedString("Specific", comment: ""),
            rows: customRows,
            emptyText: NSLocalizedString("No specific rules", comment: "")
        ))

        let divider = RulesPrototypeDivider()
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        divider.widthAnchor.constraint(equalToConstant: 292).isActive = true
        root.addArrangedSubview(divider)

        let quickActions = rpHorizontalStack(spacing: 8)
        quickActions.addArrangedSubview(makePopoverActionButton(
            title: NSLocalizedString("Device", comment: ""),
            symbol: "plus",
            enabled: currentDevice != nil
        ) { [weak self] in
            self?.rulePopover?.close()
            self?.addRule(.currentDevice)
        })
        quickActions.addArrangedSubview(makePopoverActionButton(
            title: NSLocalizedString("App", comment: ""),
            symbol: "app.badge",
            enabled: currentDevice != nil
        ) { [weak self] in
            self?.rulePopover?.close()
            self?.addRule(.currentDeviceInApp)
        })
        quickActions.addArrangedSubview(makePopoverActionButton(
            title: NSLocalizedString("Display", comment: ""),
            symbol: "display"
        ) { [weak self] in
            self?.rulePopover?.close()
            self?.addRule(.display)
        })
        root.addArrangedSubview(quickActions)

        let management = rpHorizontalStack(spacing: 8)
        management.addArrangedSubview(makePopoverActionButton(
            title: NSLocalizedString("Scope", comment: ""),
            symbol: "scope"
        ) { [weak self] in
            self?.rulePopover?.close()
            self?.showConditionsEditor()
        })
        management.addArrangedSubview(makePopoverActionButton(
            title: NSLocalizedString("Manage", comment: ""),
            symbol: "list.bullet.rectangle"
        ) { [weak self] in
            self?.rulePopover?.close()
            self?.showRuleManager()
        })
        root.addArrangedSubview(management)

        return root
    }

    private func makeRulePickerSection(
        title: String,
        rows: [RulesPrototypeRulePickerRowModel],
        emptyText: String? = nil
    ) -> NSView {
        let stack = rpVerticalStack(spacing: 6)
        stack.addArrangedSubview(rpLabel(title, size: 11, color: .secondaryLabelColor, weight: .semibold))

        if rows.isEmpty, let emptyText {
            let label = rpLabel(emptyText, size: 12, color: .tertiaryLabelColor)
            label.heightAnchor.constraint(equalToConstant: 28).isActive = true
            stack.addArrangedSubview(label)
        } else {
            for row in rows {
                let control = RulesPrototypeRulePickerRow(row)
                control.onClick = row.action
                control.widthAnchor.constraint(equalToConstant: 292).isActive = true
                control.heightAnchor.constraint(equalToConstant: 42).isActive = true
                stack.addArrangedSubview(control)
            }
        }

        return stack
    }

    private func makePopoverActionButton(
        title: String,
        symbol: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = RulesPrototypeClosureButton(title: title, symbol: symbol, action: action)
        button.controlSize = .small
        button.isEnabled = enabled
        return button
    }

    @objc private func showRuleManagerFromPopover() {
        rulePopover?.close()
        showRuleManager()
    }

    private func showRuleManager() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Rules", comment: "")
        alert.informativeText = NSLocalizedString(
            "Use the popover list to choose a rule. Reordering and full rule management are still handled by the configuration model in this prototype.",
            comment: ""
        )
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }

    private func ruleTemplateItem(_ title: String, template: RulesPrototypeRuleTemplate) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(addRuleFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = template.rawValue
        return item
    }

    @objc private func selectFoundationRule(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = RulesPrototypeFoundationRuleKind(rawValue: rawValue) else {
            return
        }
        selectOrCreateFoundationRule(kind)
    }

    @objc private func selectRule(_ sender: NSMenuItem) {
        guard schemes.indices.contains(sender.tag) else {
            return
        }
        selectedRuleIndex = sender.tag
        renderAll()
    }

    @objc private func addRuleFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let template = RulesPrototypeRuleTemplate(rawValue: rawValue) else {
            return
        }
        addRule(template)
    }

    private func selectOrCreateFoundationRule(_ kind: RulesPrototypeFoundationRuleKind) {
        if let index = schemes.firstIndex(where: kind.matches) {
            selectedRuleIndex = index
            renderAll()
            return
        }

        var scheme = kind.makeScheme(mouseMatcher: mouseCategoryMatcher(), trackpadMatcher: trackpadCategoryMatcher())
        scheme.removeEmptyPrototypeSections()
        let insertionIndex = foundationInsertionIndex(for: kind)
        withConfigurationUndo(NSLocalizedString("Create Rule", comment: "")) {
            var configuration = configurationState.configuration
            configuration.schemes.insert(scheme, at: insertionIndex)
            configurationState.configuration = configuration
        }
        selectedRuleIndex = insertionIndex
        renderAll()
    }

    private func foundationInsertionIndex(for kind: RulesPrototypeFoundationRuleKind) -> Int {
        let previousKinds = RulesPrototypeFoundationRuleKind.allCases.prefix { $0 != kind }
        return previousKinds
            .compactMap { previous in schemes.firstIndex(where: previous.matches) }
            .max()
            .map { $0 + 1 } ?? 0
    }

    private var customRuleIndices: [Int] {
        schemes.indices.filter { RulesPrototypeFoundationRuleKind.kind(for: schemes[$0]) == nil }
    }

    private func addRule(_ template: RulesPrototypeRuleTemplate) {
        var scheme = Scheme()
        switch template {
        case .currentDevice:
            scheme.if = [Scheme.If(device: currentDeviceMatcher())]
        case .currentDeviceInApp:
            guard let bundleIdentifier = chooseApplicationBundleIdentifier() else {
                return
            }
            scheme.if = [Scheme.If(device: currentDeviceMatcher(), app: bundleIdentifier)]
        case .allMiceInApp:
            guard let bundleIdentifier = chooseApplicationBundleIdentifier() else {
                return
            }
            scheme.if = [Scheme.If(device: mouseCategoryMatcher(), app: bundleIdentifier)]
        case .display:
            guard let display = ScreenManager.shared.currentScreenName else {
                return
            }
            scheme.if = [Scheme.If(display: display)]
        case .blank:
            scheme.if = [Scheme.If()]
        }

        withConfigurationUndo(NSLocalizedString("Create Rule", comment: "")) {
            var configuration = configurationState.configuration
            configuration.schemes.append(scheme)
            configurationState.configuration = configuration
        }
        selectedRuleIndex = configurationState.configuration.schemes.count - 1
        organizeFoundationRules()
        renderAll()
    }

    @objc private func duplicateSelectedRule() {
        guard schemes.indices.contains(selectedRuleIndex) else {
            return
        }
        var copy = schemes[selectedRuleIndex]
        if let name = copy.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            copy.name = String(format: NSLocalizedString("%@ Copy", comment: ""), name)
        }
        let insertionIndex = selectedRuleIndex + 1
        withConfigurationUndo(NSLocalizedString("Duplicate Rule", comment: "")) {
            var configuration = configurationState.configuration
            configuration.schemes.insert(copy, at: insertionIndex)
            configurationState.configuration = configuration
        }
        selectedRuleIndex = insertionIndex
        renderAll()
    }

    @objc private func deleteSelectedRule() {
        guard schemes.indices.contains(selectedRuleIndex),
              RulesPrototypeFoundationRuleKind.kind(for: schemes[selectedRuleIndex]) == nil else {
            return
        }
        withConfigurationUndo(NSLocalizedString("Delete Rule", comment: "")) {
            var configuration = configurationState.configuration
            configuration.schemes.remove(at: selectedRuleIndex)
            configurationState.configuration = configuration
        }
        normalizeSelection()
        renderAll()
    }

    @objc private func clearSelectedRuleSettings() {
        guard schemes.indices.contains(selectedRuleIndex) else {
            return
        }
        updateSelectedRule(NSLocalizedString("Clear Rule Settings", comment: "")) {
            $0.$pointer = nil
            $0.$scrolling = nil
            $0.$buttons = nil
        }
    }

    @objc private func showGeneralSettings() {
        presentAsSheet(GeneralSettingsViewController())
    }

    @objc private func showConditionsEditor() {
        presentAsSheet(RulesPrototypeConditionsViewController(selectedRuleIndex: selectedRuleIndex))
    }

    private func organizeFoundationRules() {
        let selected = selectedScheme
        var foundations = [RulesPrototypeFoundationRuleKind: Scheme]()
        var custom = [Scheme]()
        for scheme in schemes {
            if let kind = RulesPrototypeFoundationRuleKind.kind(for: scheme), foundations[kind] == nil {
                foundations[kind] = scheme
            } else {
                custom.append(scheme)
            }
        }
        let ordered = RulesPrototypeFoundationRuleKind.allCases.compactMap { foundations[$0] } + custom
        guard ordered != schemes else {
            return
        }
        withConfigurationUndo(NSLocalizedString("Reorder Rules", comment: "")) {
            var configuration = configurationState.configuration
            configuration.schemes = ordered
            configurationState.configuration = configuration
        }
        if let selected, let index = ordered.firstIndex(of: selected) {
            selectedRuleIndex = index
        } else {
            normalizeSelection()
        }
    }

    private func chooseApplicationBundleIdentifier() -> String? {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Choose Application", comment: "")
        panel.prompt = NSLocalizedString("Choose", comment: "")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedFileTypes = ["app"]

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
            return nil
        }
        return bundleIdentifier
    }

    private func currentDeviceMatcher() -> DeviceMatcher {
        currentDevice.map { DeviceMatcher(of: $0) } ?? mouseCategoryMatcher()
    }

    private func mouseCategoryMatcher() -> DeviceMatcher {
        DeviceMatcher(vendorID: nil, productID: nil, productName: nil, serialNumber: nil, category: [.mouse])
    }

    private func trackpadCategoryMatcher() -> DeviceMatcher {
        DeviceMatcher(vendorID: nil, productID: nil, productName: nil, serialNumber: nil, category: [.trackpad])
    }
}

private final class RulesPrototypeUndoTarget: NSObject {
    weak var configurationState: ConfigurationState?
    weak var undoManager: UndoManager?

    func restore(_ configuration: Configuration, actionName: String) {
        guard let configurationState else {
            return
        }
        let current = configurationState.configuration
        configurationState.configuration = configuration
        undoManager?.registerUndo(withTarget: self) { target in
            target.restore(current, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }
}

private final class RulesPrototypeConditionsViewController: NSViewController, NSTextFieldDelegate {
    private let configurationState = ConfigurationState.shared
    private let deviceState = DeviceState.shared
    private let selectedRuleIndex: Int
    private let contentStack = NSStackView()
    private var subscription: AnyCancellable?

    init(selectedRuleIndex: Int) {
        self.selectedRuleIndex = selectedRuleIndex
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 620, height: 620)
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
        buildView()
        render()
        subscription = configurationState.$configuration
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.render()
            }
    }

    private var selectedScheme: Scheme? {
        guard configurationState.configuration.schemes.indices.contains(selectedRuleIndex) else {
            return nil
        }
        return configurationState.configuration.schemes[selectedRuleIndex]
    }

    private var currentDevice: Device? {
        deviceState.currentDeviceRef?.value
    }

    private func buildView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        rpPin(scrollView, to: view)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 16
        contentStack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    private func render() {
        rpRemoveArrangedSubviews(from: contentStack)

        contentStack.addArrangedSubview(rpLabel(NSLocalizedString("Applies To", comment: ""), size: 24, weight: .bold))
        let note = rpLabel(
            NSLocalizedString(
                "A rule applies when any group matches. Inside a group, all fields must match.",
                comment: ""
            ),
            color: .secondaryLabelColor
        )
        note.lineBreakMode = .byWordWrapping
        contentStack.addArrangedSubview(note)

        let conditions = targetConditions(selectedScheme)
        for (index, condition) in conditions.enumerated() {
            contentStack.addArrangedSubview(makeConditionCard(condition, index: index, canDelete: conditions.count > 1))
        }

        let footer = rpHorizontalStack(spacing: 8)
        let addGroup = NSButton(
            title: NSLocalizedString("Add OR Group", comment: ""),
            target: self,
            action: #selector(addConditionGroup)
        )
        footer.addArrangedSubview(addGroup)
        footer.addArrangedSubview(rpFlexibleSpace())
        let done = NSButton(title: NSLocalizedString("Done", comment: ""), target: self, action: #selector(done))
        done.keyEquivalent = "\r"
        footer.addArrangedSubview(done)
        contentStack.addArrangedSubview(footer)
    }

    private func makeConditionCard(_ condition: Scheme.If, index: Int, canDelete: Bool) -> NSView {
        let card = RulesPrototypeCardView()
        let stack = rpVerticalStack(spacing: 12)
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        card.addSubview(stack)
        rpPin(stack, to: card)

        let header = rpHorizontalStack(spacing: 8)
        header.addArrangedSubview(rpLabel(
            String(format: NSLocalizedString("Match Group %d", comment: ""), index + 1),
            size: 14,
            weight: .semibold
        ))
        header.addArrangedSubview(rpFlexibleSpace())
        if canDelete {
            let remove = NSButton(
                title: NSLocalizedString("Remove", comment: ""),
                target: self,
                action: #selector(removeConditionGroup(_:))
            )
            remove.tag = index
            header.addArrangedSubview(remove)
        }
        stack.addArrangedSubview(header)

        stack.addArrangedSubview(makeDeviceRow(condition.device, index: index))
        stack.addArrangedSubview(makeTextConditionRow(
            title: NSLocalizedString("App", comment: ""),
            key: .app,
            value: condition.app,
            index: index,
            chooseTitle: NSLocalizedString("Choose…", comment: "")
        ))
        stack.addArrangedSubview(makeTextConditionRow(
            title: NSLocalizedString("Parent App", comment: ""),
            key: .parentApp,
            value: condition.parentApp,
            index: index,
            chooseTitle: NSLocalizedString("Choose…", comment: "")
        ))
        stack.addArrangedSubview(makeTextConditionRow(
            title: NSLocalizedString("Group App", comment: ""),
            key: .groupApp,
            value: condition.groupApp,
            index: index,
            chooseTitle: NSLocalizedString("Choose…", comment: "")
        ))
        stack.addArrangedSubview(makeTextConditionRow(
            title: NSLocalizedString("Process Name", comment: ""),
            key: .processName,
            value: condition.processName,
            index: index,
            chooseTitle: nil
        ))
        stack.addArrangedSubview(makeTextConditionRow(
            title: NSLocalizedString("Process Path", comment: ""),
            key: .processPath,
            value: condition.processPath,
            index: index,
            chooseTitle: NSLocalizedString("Choose…", comment: "")
        ))
        stack.addArrangedSubview(makeTextConditionRow(
            title: NSLocalizedString("Display", comment: ""),
            key: .display,
            value: condition.display,
            index: index,
            chooseTitle: NSLocalizedString("Current", comment: "")
        ))

        return card
    }

    private func makeDeviceRow(_ matcher: DeviceMatcher?, index: Int) -> NSView {
        let row = rpHorizontalStack(spacing: 10)
        row.addArrangedSubview(rpLabel(NSLocalizedString("Device", comment: ""), width: 110))

        let popup = NSPopUpButton()
        popup.tag = index
        popup.target = self
        popup.action = #selector(deviceChanged(_:))
        let choices: [(String, String)] = [
            (NSLocalizedString("Any Device", comment: ""), "any"),
            (NSLocalizedString("All Mice", comment: ""), "mouse"),
            (NSLocalizedString("All Trackpads", comment: ""), "trackpad"),
            (NSLocalizedString("This Device", comment: ""), "current")
        ]
        for (title, value) in choices {
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = value
        }

        if matcher == nil {
            popup.selectItem(withTitle: NSLocalizedString("Any Device", comment: ""))
        } else if matcher?.category == [.mouse], matcher?.vendorID == nil, matcher?.productID == nil {
            popup.selectItem(withTitle: NSLocalizedString("All Mice", comment: ""))
        } else if matcher?.category == [.trackpad], matcher?.vendorID == nil, matcher?.productID == nil {
            popup.selectItem(withTitle: NSLocalizedString("All Trackpads", comment: ""))
        } else {
            popup.selectItem(withTitle: NSLocalizedString("This Device", comment: ""))
        }

        row.addArrangedSubview(popup)
        row.addArrangedSubview(rpFlexibleSpace())
        return row
    }

    private func makeTextConditionRow(
        title: String,
        key: RulesPrototypeConditionTextKey,
        value: String?,
        index: Int,
        chooseTitle: String?
    ) -> NSView {
        let row = rpHorizontalStack(spacing: 8)
        row.addArrangedSubview(rpLabel(title, width: 110))

        let field = NSTextField(string: value ?? "")
        field.placeholderString = NSLocalizedString("Any", comment: "")
        field.identifier = NSUserInterfaceItemIdentifier("condition.\(key.rawValue).\(index)")
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        row.addArrangedSubview(field)

        if let chooseTitle {
            let choose = NSButton(title: chooseTitle, target: self, action: #selector(chooseConditionValue(_:)))
            choose.identifier = field.identifier
            row.addArrangedSubview(choose)
        }

        let clear = NSButton(
            title: NSLocalizedString("Clear", comment: ""),
            target: self,
            action: #selector(clearConditionValue(_:))
        )
        clear.identifier = field.identifier
        clear.isEnabled = value != nil
        row.addArrangedSubview(clear)
        row.addArrangedSubview(rpFlexibleSpace())
        return row
    }

    private func targetConditions(_ scheme: Scheme?) -> [Scheme.If] {
        guard let conditions = scheme?.if, !conditions.isEmpty else {
            return [Scheme.If()]
        }
        return conditions
    }

    private func updateCondition(at index: Int, _ update: (inout Scheme.If) -> Void) {
        updateRule {
            var conditions = targetConditions($0)
            while conditions.count <= index {
                conditions.append(Scheme.If())
            }
            update(&conditions[index])
            let compacted = conditions.filter { !$0.prototypeIsEmpty }
            $0.if = compacted.isEmpty ? nil : compacted
        }
    }

    private func updateRule(_ update: (inout Scheme) -> Void) {
        var configuration = configurationState.configuration
        guard configuration.schemes.indices.contains(selectedRuleIndex) else {
            return
        }
        update(&configuration.schemes[selectedRuleIndex])
        configurationState.configuration = configuration
    }

    @objc private func deviceChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String else {
            return
        }
        updateCondition(at: sender.tag) {
            switch rawValue {
            case "mouse":
                $0.device = mouseCategoryMatcher()
            case "trackpad":
                $0.device = trackpadCategoryMatcher()
            case "current":
                $0.device = currentDeviceMatcher()
            default:
                $0.device = nil
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
        guard let parsed = parseIdentifier(field.identifier?.rawValue) else {
            return
        }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        setValue(value.isEmpty ? nil : value, key: parsed.key, index: parsed.index)
    }

    @objc private func chooseConditionValue(_ sender: NSButton) {
        guard let parsed = parseIdentifier(sender.identifier?.rawValue) else {
            return
        }

        let value: String?
        switch parsed.key {
        case .app, .parentApp, .groupApp:
            value = chooseApplicationBundleIdentifier()
        case .processPath:
            value = chooseExecutablePath()
        case .display:
            value = ScreenManager.shared.currentScreenName
        case .processName:
            value = nil
        }

        guard let value else {
            return
        }
        setValue(value, key: parsed.key, index: parsed.index)
    }

    @objc private func clearConditionValue(_ sender: NSButton) {
        guard let parsed = parseIdentifier(sender.identifier?.rawValue) else {
            return
        }
        setValue(nil, key: parsed.key, index: parsed.index)
    }

    @objc private func addConditionGroup() {
        updateRule {
            var conditions = targetConditions($0)
            conditions.append(Scheme.If())
            $0.if = conditions
        }
    }

    @objc private func removeConditionGroup(_ sender: NSButton) {
        updateRule {
            guard var conditions = $0.if, conditions.indices.contains(sender.tag) else {
                return
            }
            conditions.remove(at: sender.tag)
            $0.if = conditions.isEmpty ? nil : conditions
        }
    }

    @objc private func done() {
        dismiss(nil)
    }

    private func setValue(_ value: String?, key: RulesPrototypeConditionTextKey, index: Int) {
        updateCondition(at: index) {
            switch key {
            case .app:
                $0.app = value
            case .parentApp:
                $0.parentApp = value
            case .groupApp:
                $0.groupApp = value
            case .processName:
                $0.processName = value
            case .processPath:
                $0.processPath = value
            case .display:
                $0.display = value
            }
        }
    }

    private func parseIdentifier(_ identifier: String?) -> (key: RulesPrototypeConditionTextKey, index: Int)? {
        guard let identifier else {
            return nil
        }
        let parts = identifier.split(separator: ".")
        guard parts.count == 3,
              let key = RulesPrototypeConditionTextKey(rawValue: String(parts[1])),
              let index = Int(parts[2]) else {
            return nil
        }
        return (key, index)
    }

    private func chooseApplicationBundleIdentifier() -> String? {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Choose Application", comment: "")
        panel.prompt = NSLocalizedString("Choose", comment: "")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedFileTypes = ["app"]

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
            return nil
        }
        return bundleIdentifier
    }

    private func chooseExecutablePath() -> String? {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Choose Executable", comment: "")
        panel.prompt = NSLocalizedString("Choose", comment: "")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url?.path
    }

    private func currentDeviceMatcher() -> DeviceMatcher {
        currentDevice.map { DeviceMatcher(of: $0) } ?? mouseCategoryMatcher()
    }

    private func mouseCategoryMatcher() -> DeviceMatcher {
        DeviceMatcher(vendorID: nil, productID: nil, productName: nil, serialNumber: nil, category: [.mouse])
    }

    private func trackpadCategoryMatcher() -> DeviceMatcher {
        DeviceMatcher(vendorID: nil, productID: nil, productName: nil, serialNumber: nil, category: [.trackpad])
    }
}

private enum RulesPrototypeConditionTextKey: String {
    case app
    case parentApp
    case groupApp
    case processName
    case processPath
    case display
}

private enum RulesPrototypeRecordingTarget: Equatable {
    case mapping(index: Int)
    case autoScrollTrigger
    case gestureTrigger
}

private enum RulesPrototypeMappingActionChoice: Equatable {
    case arg0(Scheme.Buttons.Mapping.Action.Arg0)
    case run
    case mouseWheelScrollUp
    case mouseWheelScrollDown
    case mouseWheelScrollLeft
    case mouseWheelScrollRight
    case keyPress

    static var all: [Self] {
        Scheme.Buttons.Mapping.Action.Arg0.allCases.map(arg0) + [
            .keyPress,
            .mouseWheelScrollUp,
            .mouseWheelScrollDown,
            .mouseWheelScrollLeft,
            .mouseWheelScrollRight,
            .run
        ]
    }

    static func choice(for action: Scheme.Buttons.Mapping.Action?) -> Self {
        switch action {
        case let .arg0(value):
            return .arg0(value)
        case .arg1(.run):
            return .run
        case .arg1(.mouseWheelScrollUp):
            return .mouseWheelScrollUp
        case .arg1(.mouseWheelScrollDown):
            return .mouseWheelScrollDown
        case .arg1(.mouseWheelScrollLeft):
            return .mouseWheelScrollLeft
        case .arg1(.mouseWheelScrollRight):
            return .mouseWheelScrollRight
        case .arg1(.keyPress):
            return .keyPress
        case nil:
            return .arg0(.auto)
        }
    }

    var title: String {
        switch self {
        case let .arg0(value):
            return value.description
        case .run:
            return NSLocalizedString("Run shell command…", comment: "")
        case .mouseWheelScrollUp:
            return NSLocalizedString("Scroll up…", comment: "")
        case .mouseWheelScrollDown:
            return NSLocalizedString("Scroll down…", comment: "")
        case .mouseWheelScrollLeft:
            return NSLocalizedString("Scroll left…", comment: "")
        case .mouseWheelScrollRight:
            return NSLocalizedString("Scroll right…", comment: "")
        case .keyPress:
            return NSLocalizedString("Keyboard shortcut…", comment: "")
        }
    }

    func action(preserving current: Scheme.Buttons.Mapping.Action?) -> Scheme.Buttons.Mapping.Action {
        switch self {
        case let .arg0(value):
            return .arg0(value)
        case .run:
            if case .arg1(.run) = current {
                return current ?? .arg1(.run(""))
            }
            return .arg1(.run(""))
        case .mouseWheelScrollUp:
            if case .arg1(.mouseWheelScrollUp) = current {
                return current ?? .arg1(.mouseWheelScrollUp(.line(3)))
            }
            return .arg1(.mouseWheelScrollUp(.line(3)))
        case .mouseWheelScrollDown:
            if case .arg1(.mouseWheelScrollDown) = current {
                return current ?? .arg1(.mouseWheelScrollDown(.line(3)))
            }
            return .arg1(.mouseWheelScrollDown(.line(3)))
        case .mouseWheelScrollLeft:
            if case .arg1(.mouseWheelScrollLeft) = current {
                return current ?? .arg1(.mouseWheelScrollLeft(.line(3)))
            }
            return .arg1(.mouseWheelScrollLeft(.line(3)))
        case .mouseWheelScrollRight:
            if case .arg1(.mouseWheelScrollRight) = current {
                return current ?? .arg1(.mouseWheelScrollRight(.line(3)))
            }
            return .arg1(.mouseWheelScrollRight(.line(3)))
        case .keyPress:
            if case .arg1(.keyPress) = current {
                return current ?? .arg1(.keyPress([]))
            }
            return .arg1(.keyPress([]))
        }
    }
}

private struct RulesPrototypeSettingsSection {
    let id: String
    let title: String
    let subtitle: String
    let group: RulesPrototypeSettingGroup
    let keys: [RulesPrototypeSettingKey]

    var symbol: String {
        keys.first?.symbol ?? group.symbol
    }

    static let pointerMovement = Self(
        id: "pointer.movement",
        title: NSLocalizedString("Pointer Movement", comment: ""),
        subtitle: NSLocalizedString("Speed and acceleration", comment: ""),
        group: .pointer,
        keys: [.pointerSpeed, .pointerAcceleration]
    )

    static func sections(for group: RulesPrototypeSettingGroup) -> [Self] {
        switch group {
        case .pointer:
            return [
                pointerMovement,
                .init(
                    id: "pointer.toScroll",
                    title: NSLocalizedString("Pointer to Scroll", comment: ""),
                    subtitle: NSLocalizedString("Use movement as scrolling", comment: ""),
                    group: .pointer,
                    keys: [.redirectsToScroll]
                )
            ]
        case .scroll:
            return [
                .init(
                    id: "scroll.direction",
                    title: NSLocalizedString("Scroll Direction", comment: ""),
                    subtitle: NSLocalizedString("Reverse vertical or horizontal scroll", comment: ""),
                    group: .scroll,
                    keys: [.reverseVertical, .reverseHorizontal]
                ),
                .init(
                    id: "scroll.behavior",
                    title: NSLocalizedString("Scroll Behavior", comment: ""),
                    subtitle: NSLocalizedString("Accelerated, linear, or smoothed", comment: ""),
                    group: .scroll,
                    keys: [.scrollMode]
                ),
                .init(
                    id: "scroll.modifiers",
                    title: NSLocalizedString("Modifier Keys", comment: ""),
                    subtitle: NSLocalizedString("Change scroll while holding keys", comment: ""),
                    group: .scroll,
                    keys: [.scrollModifiers]
                )
            ]
        case .buttons:
            return [
                .init(
                    id: "buttons.navigation",
                    title: NSLocalizedString("Navigation", comment: ""),
                    subtitle: NSLocalizedString("Back, forward, and primary buttons", comment: ""),
                    group: .buttons,
                    keys: [.universalBackForward, .switchPrimary]
                ),
                .init(
                    id: "buttons.mappings",
                    title: NSLocalizedString("Button Mappings", comment: ""),
                    subtitle: NSLocalizedString("Record a button and choose an action", comment: ""),
                    group: .buttons,
                    keys: [.buttonMappings]
                ),
                .init(
                    id: "buttons.autoScroll",
                    title: NSLocalizedString("Auto Scroll", comment: ""),
                    subtitle: NSLocalizedString("Scroll from a button trigger", comment: ""),
                    group: .buttons,
                    keys: [.autoScroll]
                ),
                .init(
                    id: "buttons.gesture",
                    title: NSLocalizedString("Gesture Button", comment: ""),
                    subtitle: NSLocalizedString("Actions for gesture directions", comment: ""),
                    group: .buttons,
                    keys: [.gesture]
                ),
                .init(
                    id: "buttons.debouncing",
                    title: NSLocalizedString("Click Debouncing", comment: ""),
                    subtitle: NSLocalizedString("Filter rapid duplicate clicks", comment: ""),
                    group: .buttons,
                    keys: [.clickDebouncing]
                )
            ]
        }
    }
}

private enum RulesPrototypeSidebarListRow {
    static let columnIdentifier = NSUserInterfaceItemIdentifier("RulesPrototypeSidebarListColumn")

    case group(RulesPrototypeSettingGroup)
    case section(RulesPrototypeSettingsSection, hasSettings: Bool)
}

private enum RulesPrototypeSettingGroup: String, CaseIterable {
    case pointer
    case scroll
    case buttons

    var title: String {
        switch self {
        case .pointer:
            return NSLocalizedString("Pointing", comment: "")
        case .scroll:
            return NSLocalizedString("Scrolling", comment: "")
        case .buttons:
            return NSLocalizedString("Buttons", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .pointer:
            return "cursorarrow.motionlines"
        case .scroll:
            return "scroll"
        case .buttons:
            return "button.programmable"
        }
    }
}

private enum RulesPrototypeSettingKey: String, CaseIterable {
    case pointerSpeed
    case pointerAcceleration
    case disablePointerAcceleration
    case reverseVertical
    case reverseHorizontal
    case redirectsToScroll
    case universalBackForward
    case switchPrimary
    case scrollMode
    case scrollDistance
    case scrollDistanceHorizontal
    case scrollAcceleration
    case scrollAccelerationHorizontal
    case scrollSpeed
    case scrollSpeedHorizontal
    case smoothedScrolling
    case scrollModifiers
    case buttonMappings
    case clickDebouncing
    case autoScroll
    case autoScrollOptions
    case gesture
    case gestureOptions

    static var visibleCases: [Self] {
        [
            .pointerSpeed,
            .pointerAcceleration,
            .redirectsToScroll,
            .scrollMode,
            .reverseVertical,
            .reverseHorizontal,
            .scrollModifiers,
            .universalBackForward,
            .buttonMappings,
            .autoScroll,
            .gesture,
            .switchPrimary,
            .clickDebouncing
        ]
    }

    var title: String {
        switch self {
        case .pointerSpeed:
            return NSLocalizedString("Pointer speed", comment: "")
        case .pointerAcceleration:
            return NSLocalizedString("Pointer acceleration", comment: "")
        case .disablePointerAcceleration:
            return NSLocalizedString("Disable pointer acceleration", comment: "")
        case .reverseVertical:
            return NSLocalizedString("Reverse vertical scrolling", comment: "")
        case .reverseHorizontal:
            return NSLocalizedString("Reverse horizontal scrolling", comment: "")
        case .redirectsToScroll:
            return NSLocalizedString("Convert pointer movement to scroll events", comment: "")
        case .universalBackForward:
            return NSLocalizedString("Back and forward", comment: "")
        case .switchPrimary:
            return NSLocalizedString("Switch primary and secondary buttons", comment: "")
        case .scrollMode:
            return NSLocalizedString("Scroll behavior", comment: "")
        case .scrollDistance:
            return NSLocalizedString("Scroll distance", comment: "")
        case .scrollDistanceHorizontal:
            return NSLocalizedString("Horizontal scroll distance", comment: "")
        case .scrollAcceleration:
            return NSLocalizedString("Scroll acceleration", comment: "")
        case .scrollAccelerationHorizontal:
            return NSLocalizedString("Horizontal scroll acceleration", comment: "")
        case .scrollSpeed:
            return NSLocalizedString("Scroll speed", comment: "")
        case .scrollSpeedHorizontal:
            return NSLocalizedString("Horizontal scroll speed", comment: "")
        case .smoothedScrolling:
            return NSLocalizedString("Smooth scrolling", comment: "")
        case .scrollModifiers:
            return NSLocalizedString("Scroll modifiers", comment: "")
        case .buttonMappings:
            return NSLocalizedString("Button mappings", comment: "")
        case .clickDebouncing:
            return NSLocalizedString("Click debouncing", comment: "")
        case .autoScroll:
            return NSLocalizedString("Auto scroll", comment: "")
        case .autoScrollOptions:
            return NSLocalizedString("Auto scroll options", comment: "")
        case .gesture:
            return NSLocalizedString("Gesture button", comment: "")
        case .gestureOptions:
            return NSLocalizedString("Gesture options", comment: "")
        }
    }

    var shortDescription: String {
        switch self {
        case .pointerSpeed:
            return NSLocalizedString("Pointer speed", comment: "")
        case .pointerAcceleration:
            return NSLocalizedString("Pointer acceleration", comment: "")
        case .disablePointerAcceleration:
            return NSLocalizedString("Use raw pointer movement", comment: "")
        case .reverseVertical:
            return NSLocalizedString("Invert vertical wheel movement", comment: "")
        case .reverseHorizontal:
            return NSLocalizedString("Invert horizontal wheel movement", comment: "")
        case .redirectsToScroll:
            return NSLocalizedString("Scrolling settings are applied to converted events.", comment: "")
        case .universalBackForward:
            return NSLocalizedString("Side buttons navigate back and forward", comment: "")
        case .switchPrimary:
            return NSLocalizedString("Swap primary and secondary buttons", comment: "")
        case .scrollMode:
            return NSLocalizedString("Choose one scrolling model", comment: "")
        case .scrollDistance:
            return NSLocalizedString("Fixed vertical scroll distance", comment: "")
        case .scrollDistanceHorizontal:
            return NSLocalizedString("Fixed horizontal scroll distance", comment: "")
        case .scrollAcceleration:
            return NSLocalizedString("Vertical scroll acceleration", comment: "")
        case .scrollAccelerationHorizontal:
            return NSLocalizedString("Horizontal scroll acceleration", comment: "")
        case .scrollSpeed:
            return NSLocalizedString("Vertical scroll speed", comment: "")
        case .scrollSpeedHorizontal:
            return NSLocalizedString("Horizontal scroll speed", comment: "")
        case .smoothedScrolling:
            return NSLocalizedString("Tune momentum-like scrolling", comment: "")
        case .scrollModifiers:
            return NSLocalizedString("Change scrolling while holding keys", comment: "")
        case .buttonMappings:
            return NSLocalizedString("Assign actions to mouse buttons", comment: "")
        case .clickDebouncing:
            return NSLocalizedString("Filter repeated clicks", comment: "")
        case .autoScroll:
            return NSLocalizedString("Trigger, mode, and speed", comment: "")
        case .autoScrollOptions:
            return NSLocalizedString("Trigger and speed for auto scroll", comment: "")
        case .gesture:
            return NSLocalizedString("Trigger and drag actions", comment: "")
        case .gestureOptions:
            return NSLocalizedString("Actions for gesture directions", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .pointerSpeed:
            return "cursorarrow.motionlines"
        case .pointerAcceleration:
            return "speedometer"
        case .disablePointerAcceleration:
            return "bolt.slash"
        case .reverseVertical:
            return "arrow.up.arrow.down"
        case .reverseHorizontal:
            return "arrow.left.arrow.right"
        case .redirectsToScroll:
            return "arrow.up.and.down.and.arrow.left.and.right"
        case .universalBackForward:
            return "arrow.left.arrow.right"
        case .switchPrimary:
            return "rectangle.lefthalf.inset.filled.arrow.left"
        case .scrollMode:
            return "slider.horizontal.3"
        case .scrollDistance:
            return "scroll"
        case .scrollDistanceHorizontal:
            return "arrow.left.and.right"
        case .scrollAcceleration:
            return "gauge.with.dots.needle.67percent"
        case .scrollAccelerationHorizontal:
            return "gauge.with.dots.needle.67percent"
        case .scrollSpeed:
            return "hare"
        case .scrollSpeedHorizontal:
            return "hare"
        case .smoothedScrolling:
            return "waveform.path"
        case .scrollModifiers:
            return "command"
        case .buttonMappings:
            return "button.programmable"
        case .clickDebouncing:
            return "timer"
        case .autoScroll:
            return "arrow.down.circle"
        case .autoScrollOptions:
            return "slider.horizontal.3"
        case .gesture:
            return "hand.draw"
        case .gestureOptions:
            return "slider.horizontal.3"
        }
    }

    static func settings(in scheme: Scheme) -> [Self] {
        visibleCases.filter { $0.isSet(in: scheme) }
    }

    func isSet(in scheme: Scheme) -> Bool {
        switch self {
        case .pointerSpeed:
            return scheme.$pointer?.speed != nil
        case .pointerAcceleration:
            return scheme.$pointer?.acceleration != nil || scheme.$pointer?.disableAcceleration != nil
        case .disablePointerAcceleration:
            return scheme.$pointer?.disableAcceleration != nil
        case .reverseVertical:
            return scheme.$scrolling?.$reverse?.vertical != nil
        case .reverseHorizontal:
            return scheme.$scrolling?.$reverse?.horizontal != nil
        case .redirectsToScroll:
            return scheme.$pointer?.redirectsToScroll != nil
        case .universalBackForward:
            return scheme.$buttons?.universalBackForward != nil
        case .switchPrimary:
            return scheme.$buttons?.switchPrimaryButtonAndSecondaryButtons != nil
        case .scrollMode:
            return scheme.$scrolling?.$distance != nil ||
                scheme.$scrolling?.$acceleration != nil ||
                scheme.$scrolling?.$speed != nil ||
                scheme.$scrolling?.$smoothed != nil
        case .scrollDistance:
            return scheme.$scrolling?.$distance?.vertical != nil
        case .scrollDistanceHorizontal:
            return scheme.$scrolling?.$distance?.horizontal != nil
        case .scrollAcceleration:
            return scheme.$scrolling?.$acceleration?.vertical != nil
        case .scrollAccelerationHorizontal:
            return scheme.$scrolling?.$acceleration?.horizontal != nil
        case .scrollSpeed:
            return scheme.$scrolling?.$speed?.vertical != nil
        case .scrollSpeedHorizontal:
            return scheme.$scrolling?.$speed?.horizontal != nil
        case .smoothedScrolling:
            return scheme.$scrolling?.$smoothed != nil
        case .scrollModifiers:
            return scheme.$scrolling?.$modifiers != nil
        case .buttonMappings:
            return scheme.$buttons?.mappings != nil
        case .clickDebouncing:
            return scheme.$buttons?.$clickDebouncing != nil
        case .autoScroll:
            return scheme.$buttons?.$autoScroll != nil
        case .autoScrollOptions:
            return scheme.$buttons?.$autoScroll?.prototypeHasOptions == true
        case .gesture:
            return scheme.$buttons?.$gesture != nil
        case .gestureOptions:
            return scheme.$buttons?.$gesture?.prototypeHasOptions == true
        }
    }

    func unset(in scheme: inout Scheme) {
        switch self {
        case .pointerSpeed:
            scheme.pointer.speed = nil
        case .pointerAcceleration:
            scheme.pointer.acceleration = nil
            scheme.pointer.disableAcceleration = nil
        case .disablePointerAcceleration:
            scheme.pointer.disableAcceleration = nil
        case .reverseVertical:
            scheme.scrolling.reverse.vertical = nil
        case .reverseHorizontal:
            scheme.scrolling.reverse.horizontal = nil
        case .redirectsToScroll:
            scheme.pointer.redirectsToScroll = nil
        case .universalBackForward:
            scheme.buttons.universalBackForward = nil
        case .switchPrimary:
            scheme.buttons.switchPrimaryButtonAndSecondaryButtons = nil
        case .scrollMode:
            scheme.$scrolling?.$distance = nil
            scheme.$scrolling?.$acceleration = nil
            scheme.$scrolling?.$speed = nil
            scheme.$scrolling?.$smoothed = nil
        case .scrollDistance:
            scheme.scrolling.distance.vertical = nil
        case .scrollDistanceHorizontal:
            scheme.scrolling.distance.horizontal = nil
        case .scrollAcceleration:
            scheme.scrolling.acceleration.vertical = nil
        case .scrollAccelerationHorizontal:
            scheme.scrolling.acceleration.horizontal = nil
        case .scrollSpeed:
            scheme.scrolling.speed.vertical = nil
        case .scrollSpeedHorizontal:
            scheme.scrolling.speed.horizontal = nil
        case .smoothedScrolling:
            scheme.$scrolling?.$smoothed = nil
        case .scrollModifiers:
            scheme.$scrolling?.$modifiers = nil
        case .buttonMappings:
            scheme.buttons.mappings = nil
        case .clickDebouncing:
            scheme.$buttons?.$clickDebouncing = nil
        case .autoScroll:
            scheme.$buttons?.$autoScroll = nil
        case .autoScrollOptions:
            scheme.$buttons?.$autoScroll?.modes = nil
            scheme.$buttons?.$autoScroll?.speed = nil
            scheme.$buttons?.$autoScroll?.preserveNativeMiddleClick = nil
            scheme.$buttons?.$autoScroll?.trigger = nil
        case .gesture:
            scheme.$buttons?.$gesture = nil
        case .gestureOptions:
            scheme.$buttons?.$gesture?.trigger = nil
            scheme.$buttons?.$gesture?.threshold = nil
            scheme.$buttons?.$gesture?.deadZone = nil
            scheme.$buttons?.$gesture?.cooldownMs = nil
            scheme.$buttons?.$gesture?.$actions = nil
        }
    }
}

private enum RulesPrototypeFoundationRuleKind: String, CaseIterable {
    case global
    case allMice
    case allTrackpads

    static var visibleCases: [Self] {
        [.allMice, .allTrackpads]
    }

    var title: String {
        switch self {
        case .global:
            return NSLocalizedString("Base Configuration", comment: "")
        case .allMice:
            return NSLocalizedString("All Mice", comment: "")
        case .allTrackpads:
            return NSLocalizedString("All Trackpads", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .global:
            return "globe"
        case .allMice:
            return "computermouse"
        case .allTrackpads:
            return "rectangle.and.hand.point.up.left"
        }
    }

    var subtitle: String {
        switch self {
        case .global:
            return NSLocalizedString("Starting point", comment: "")
        case .allMice:
            return NSLocalizedString("Mouse defaults", comment: "")
        case .allTrackpads:
            return NSLocalizedString("Trackpad defaults", comment: "")
        }
    }

    static func kind(for scheme: Scheme) -> Self? {
        if scheme.if == nil {
            return .global
        }
        guard let condition = scheme.if?.singlePrototypeCondition,
              condition.onlyHasDeviceCondition,
              let device = condition.device,
              device.vendorID == nil,
              device.productID == nil,
              device.productName == nil,
              device.serialNumber == nil else {
            return nil
        }
        if device.category == [.mouse] {
            return .allMice
        }
        if device.category == [.trackpad] {
            return .allTrackpads
        }
        return nil
    }

    func matches(_ scheme: Scheme) -> Bool {
        Self.kind(for: scheme) == self
    }

    func makeScheme(mouseMatcher: DeviceMatcher, trackpadMatcher: DeviceMatcher) -> Scheme {
        switch self {
        case .global:
            return Scheme()
        case .allMice:
            var scheme = Scheme(if: [Scheme.If(device: mouseMatcher)])
            scheme.scrolling.reverse.vertical = false
            scheme.buttons.universalBackForward = .both
            return scheme
        case .allTrackpads:
            return Scheme(if: [Scheme.If(device: trackpadMatcher)])
        }
    }
}

private enum RulesPrototypeRuleTemplate: String {
    case currentDevice
    case currentDeviceInApp
    case allMiceInApp
    case display
    case blank
}

private enum RulesPrototypeScrollMode: String, CaseIterable {
    case accelerated
    case linear
    case smoothed

    var title: String {
        switch self {
        case .accelerated:
            return NSLocalizedString("Accelerated", comment: "")
        case .linear:
            return NSLocalizedString("Linear", comment: "")
        case .smoothed:
            return NSLocalizedString("Smoothed", comment: "")
        }
    }
}

private enum RulesPrototypeLinearScrollUnit: String, CaseIterable {
    case lines
    case pixels

    var title: String {
        switch self {
        case .lines:
            return NSLocalizedString("Lines", comment: "")
        case .pixels:
            return NSLocalizedString("Pixels", comment: "")
        }
    }
}

private enum RulesPrototypeUniversalBackForwardChoice: String, CaseIterable {
    case none
    case both
    case backOnly
    case forwardOnly

    init(_ value: Scheme.Buttons.UniversalBackForward) {
        switch value {
        case .none:
            self = .none
        case .both:
            self = .both
        case .backOnly:
            self = .backOnly
        case .forwardOnly:
            self = .forwardOnly
        }
    }

    var value: Scheme.Buttons.UniversalBackForward {
        switch self {
        case .none:
            return .none
        case .both:
            return .both
        case .backOnly:
            return .backOnly
        case .forwardOnly:
            return .forwardOnly
        }
    }

    var title: String {
        switch self {
        case .none:
            return NSLocalizedString("Off", comment: "")
        case .both:
            return NSLocalizedString("Back and Forward", comment: "")
        case .backOnly:
            return NSLocalizedString("Back Only", comment: "")
        case .forwardOnly:
            return NSLocalizedString("Forward Only", comment: "")
        }
    }
}

private enum RulesPrototypeModifierChoice: Int {
    case inherit
    case defaultAction
    case ignore
    case noAction
    case alterOrientation
    case changeSpeed
    case zoom
    case pinchZoom

    static var actionCases: [Self] {
        [.defaultAction, .ignore, .noAction, .alterOrientation, .changeSpeed, .zoom, .pinchZoom]
    }

    init(action: Scheme.Scrolling.Modifiers.Action?) {
        guard let action else {
            self = .inherit
            return
        }
        switch action.kind {
        case .defaultAction:
            self = .defaultAction
        case .ignore:
            self = .ignore
        case .noAction:
            self = .noAction
        case .alterOrientation:
            self = .alterOrientation
        case .changeSpeed:
            self = .changeSpeed
        case .zoom:
            self = .zoom
        case .pinchZoom:
            self = .pinchZoom
        }
    }

    var title: String {
        switch self {
        case .inherit:
            return NSLocalizedString("Follow earlier rules", comment: "")
        case .defaultAction:
            return NSLocalizedString("Default", comment: "")
        case .ignore:
            return NSLocalizedString("Ignore", comment: "")
        case .noAction:
            return NSLocalizedString("No Action", comment: "")
        case .alterOrientation:
            return NSLocalizedString("Swap Axis", comment: "")
        case .changeSpeed:
            return NSLocalizedString("Change Speed", comment: "")
        case .zoom:
            return NSLocalizedString("Zoom", comment: "")
        case .pinchZoom:
            return NSLocalizedString("Pinch Zoom", comment: "")
        }
    }

    var action: Scheme.Scrolling.Modifiers.Action? {
        switch self {
        case .inherit:
            return nil
        case .defaultAction:
            return .auto
        case .ignore:
            return .ignore
        case .noAction:
            return .preventDefault
        case .alterOrientation:
            return .alterOrientation
        case .changeSpeed:
            return .changeSpeed(scale: 1)
        case .zoom:
            return .zoom
        case .pinchZoom:
            return .pinchZoom
        }
    }
}

private struct RulesPrototypeModifierField {
    enum Modifier: Int {
        case command
        case shift
        case option
        case control
    }

    let direction: Scheme.Scrolling.BidirectionalDirection
    let modifier: Modifier

    init(direction: Scheme.Scrolling.BidirectionalDirection, label: String) {
        self.direction = direction
        if label.contains("Shift") {
            modifier = .shift
        } else if label.contains("Option") {
            modifier = .option
        } else if label.contains("Control") {
            modifier = .control
        } else {
            modifier = .command
        }
    }

    init?(tag: Int) {
        let directionRaw = tag / 10
        let modifierRaw = tag % 10
        guard let modifier = Modifier(rawValue: modifierRaw) else {
            return nil
        }
        direction = directionRaw == 1 ? .horizontal : .vertical
        self.modifier = modifier
    }

    var tag: Int {
        (direction == .horizontal ? 1 : 0) * 10 + modifier.rawValue
    }
}

private struct RulesPrototypeMouseButtonOption {
    let title: String
    let button: CGMouseButton

    static var debouncingButtons: [Self] {
        [
            .init(title: NSLocalizedString("Primary", comment: ""), button: .left),
            .init(title: NSLocalizedString("Secondary", comment: ""), button: .right),
            .init(title: NSLocalizedString("Middle", comment: ""), button: .center),
            .init(title: NSLocalizedString("Back", comment: ""), button: .back),
            .init(title: NSLocalizedString("Forward", comment: ""), button: .forward)
        ]
    }
}

private enum RulesPrototypePresenter {
    static func scrollMode(for scheme: Scheme) -> RulesPrototypeScrollMode {
        if let smoothed = scheme.scrolling.smoothed.vertical ?? scheme.scrolling.smoothed.horizontal,
           smoothed.isEnabled {
            return .smoothed
        }

        switch scheme.scrolling.distance.vertical ?? scheme.scrolling.distance.horizontal {
        case .some(.line), .some(.pixel):
            return .linear
        case .some(.auto), nil:
            return .accelerated
        }
    }

    static func applyScrollMode(_ mode: RulesPrototypeScrollMode, to scheme: inout Scheme, inherited: Scheme) {
        switch mode {
        case .accelerated:
            scheme.$scrolling?.$smoothed = nil
            scheme.scrolling.distance.vertical = .auto
            scheme.scrolling.distance.horizontal = .auto
            scheme.scrolling.acceleration.vertical = inherited.scrolling.acceleration.vertical ?? 1
            scheme.scrolling.acceleration.horizontal = inherited.scrolling.acceleration.horizontal
                ?? inherited.scrolling.acceleration.vertical
                ?? 1
            scheme.scrolling.speed.vertical = inherited.scrolling.speed.vertical ?? 0
            scheme.scrolling.speed.horizontal = inherited.scrolling.speed.horizontal
                ?? inherited.scrolling.speed.vertical
                ?? 0

        case .linear:
            scheme.$scrolling?.$smoothed = nil
            scheme.scrolling.distance.vertical = .line(lineDistance(inherited.scrolling.distance.vertical, fallback: 3))
            scheme.scrolling.distance.horizontal = .line(
                lineDistance(
                    inherited.scrolling.distance.horizontal ?? inherited.scrolling.distance.vertical,
                    fallback: 3
                )
            )
            scheme.scrolling.acceleration.vertical = nil
            scheme.scrolling.acceleration.horizontal = nil
            scheme.scrolling.speed.vertical = nil
            scheme.scrolling.speed.horizontal = nil

        case .smoothed:
            scheme.scrolling.distance.vertical = .auto
            scheme.scrolling.distance.horizontal = .auto
            scheme.scrolling.acceleration.vertical = 1
            scheme.scrolling.acceleration.horizontal = 1
            scheme.scrolling.speed.vertical = 0
            scheme.scrolling.speed.horizontal = 0
            updateVerticalSmoothed(in: &scheme) {
                $0.enabled = true
            }
            updateHorizontalSmoothed(in: &scheme) {
                $0.enabled = true
            }
        }
    }

    static func updateVerticalSmoothed(in scheme: inout Scheme, _ update: (inout Scheme.Scrolling.Smoothed) -> Void) {
        var smoothed = scheme.scrolling.smoothed.vertical
            ?? Scheme.Scrolling.Smoothed.Preset.defaultPreset.defaultConfiguration
        update(&smoothed)
        scheme.scrolling.smoothed.vertical = smoothed
    }

    static func updateHorizontalSmoothed(in scheme: inout Scheme, _ update: (inout Scheme.Scrolling.Smoothed) -> Void) {
        var smoothed = scheme.scrolling.smoothed.horizontal
            ?? scheme.scrolling.smoothed.vertical
            ?? Scheme.Scrolling.Smoothed.Preset.defaultPreset.defaultConfiguration
        update(&smoothed)
        scheme.scrolling.smoothed.horizontal = smoothed
    }

    static func title(for scheme: Scheme, at index: Int) -> String {
        if let kind = RulesPrototypeFoundationRuleKind.kind(for: scheme) {
            return kind.title
        }

        if let name = scheme.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        guard let condition = scheme.if?.first else {
            return NSLocalizedString("Base Configuration", comment: "")
        }

        if let deviceName = condition.device?.productName {
            if let app = condition.app {
                return String(
                    format: NSLocalizedString("%@ in %@", comment: ""),
                    deviceName,
                    appName(for: app)
                )
            }
            return deviceName
        }

        if let app = condition.app {
            return appName(for: app)
        }

        if let display = condition.display {
            return display
        }

        if let category = condition.device?.category?.first {
            switch category {
            case .mouse:
                return NSLocalizedString("All Mice", comment: "")
            case .trackpad:
                return NSLocalizedString("All Trackpads", comment: "")
            }
        }

        return String(format: NSLocalizedString("Custom Rule %d", comment: ""), index + 1)
    }

    static func targetSummary(for scheme: Scheme) -> String {
        guard let condition = scheme.if?.first else {
            return NSLocalizedString("Any device · any app · any display", comment: "")
        }

        return [
            condition.device.map(deviceSummary) ?? NSLocalizedString("Any device", comment: ""),
            appTargetSummary(condition),
            condition.display ?? NSLocalizedString("Any display", comment: "")
        ].joined(separator: " · ")
    }

    static func headerSubtitle(for scheme: Scheme, settingsCount: Int) -> String {
        let settingsText = settingsCount == 1
            ? NSLocalizedString("1 setting", comment: "")
            : String(format: NSLocalizedString("%d settings", comment: ""), settingsCount)
        guard scheme.if != nil else {
            return String(format: NSLocalizedString("Always applies · %@", comment: ""), settingsText)
        }
        return "\(targetSummary(for: scheme)) · \(settingsText)"
    }

    static func symbol(for scheme: Scheme) -> String {
        guard let condition = scheme.if?.first else {
            return "globe"
        }
        if let category = condition.device?.category?.first {
            switch category {
            case .mouse:
                return "computermouse"
            case .trackpad:
                return "rectangle.and.hand.point.up.left"
            }
        }
        if condition.app != nil || condition.parentApp != nil || condition.groupApp != nil {
            return "app.badge"
        }
        if condition.processName != nil || condition.processPath != nil {
            return "terminal"
        }
        if condition.display != nil {
            return "display"
        }
        return "slider.horizontal.3"
    }

    static func appTargetSummary(_ condition: Scheme.If) -> String {
        if let app = condition.app {
            return appName(for: app)
        }
        if let processPath = condition.processPath {
            return URL(fileURLWithPath: processPath).lastPathComponent
        }
        return NSLocalizedString("Any App", comment: "")
    }

    static func deviceSummary(_ matcher: DeviceMatcher) -> String {
        if matcher.vendorID == nil, matcher.productID == nil, matcher.category == [.mouse] {
            return NSLocalizedString("All Mice", comment: "")
        }
        if matcher.vendorID == nil, matcher.productID == nil, matcher.category == [.trackpad] {
            return NSLocalizedString("All Trackpads", comment: "")
        }
        if let productName = matcher.productName {
            return productName
        }
        if let category = matcher.category?.first {
            return category.rawValue.capitalized
        }
        if let vendorID = matcher.vendorID, let productID = matcher.productID {
            return String(format: "Device %04x:%04x", vendorID, productID)
        }
        return NSLocalizedString("Any Device", comment: "")
    }

    static func appName(for bundleIdentifier: String) -> String {
        NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier)?
            .deletingPathExtension()
            .lastPathComponent ?? bundleIdentifier
    }

    static func doubleValue(_ value: Unsettable<Decimal>?, fallback: Double) -> Double {
        guard let value else {
            return fallback
        }
        switch value {
        case let .value(decimal):
            return decimal.asTruncatedDouble
        case .unset:
            return fallback
        }
    }

    static func lineDistance(_ distance: Scheme.Scrolling.Distance?, fallback: Int) -> Int {
        switch distance {
        case let .line(value):
            return value
        case let .pixel(value):
            return max(0, Int(value.asTruncatedDouble.rounded()))
        case .auto, nil:
            return fallback
        }
    }

    static func pixelDistance(_ distance: Scheme.Scrolling.Distance?, fallback: Double) -> Double {
        switch distance {
        case let .pixel(value):
            return value.asTruncatedDouble
        case let .line(value):
            return Double(value * 12)
        case .auto, nil:
            return fallback
        }
    }

    static func lineDistanceValue(_ distance: Scheme.Scrolling.Distance?, fallback: Int) -> Int {
        lineDistance(distance, fallback: fallback)
    }

    static func blankMapping() -> Scheme.Buttons.Mapping {
        Scheme.Buttons.Mapping()
    }

    static func defaultTriggerMapping() -> Scheme.Buttons.Mapping {
        var mapping = Scheme.Buttons.Mapping()
        mapping.button = .mouse(2)
        return mapping
    }

    static func sanitizedTrigger(_ mapping: Scheme.Buttons.Mapping) -> Scheme.Buttons.Mapping {
        var trigger = mapping
        trigger.action = nil
        trigger.repeat = nil
        trigger.hold = nil
        trigger.scroll = nil
        return trigger
    }

    static func mapping(from event: CGEvent) -> Scheme.Buttons.Mapping? {
        var mapping = Scheme.Buttons.Mapping()
        mapping.modifierFlags = event.flags
        switch event.type {
        case .flagsChanged:
            break
        case .leftMouseDown, .leftMouseUp:
            mapping.button = .mouse(Int(CGMouseButton.left.rawValue))
        case .rightMouseDown, .rightMouseUp:
            mapping.button = .mouse(Int(CGMouseButton.right.rawValue))
        case .otherMouseDown, .otherMouseUp:
            mapping.button = .mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        case .scrollWheel:
            let scrollWheelEventView = ScrollWheelEventView(event)
            if scrollWheelEventView.deltaYSignum < 0 {
                mapping.scroll = .down
            } else if scrollWheelEventView.deltaYSignum > 0 {
                mapping.scroll = .up
            } else if scrollWheelEventView.deltaXSignum < 0 {
                mapping.scroll = .right
            } else if scrollWheelEventView.deltaXSignum > 0 {
                mapping.scroll = .left
            }
        default:
            return nil
        }
        return mapping
    }

    static func mappingTargetTitle(_ mapping: Scheme.Buttons.Mapping) -> String {
        let modifierPrefix = mappingModifierTitle(mapping)
        if let button = mapping.button {
            let title: String
            switch button {
            case let .mouse(number):
                switch CGMouseButton(rawValue: UInt32(number)) {
                case .some(.left):
                    title = NSLocalizedString("Primary Button", comment: "")
                case .some(.right):
                    title = NSLocalizedString("Secondary Button", comment: "")
                case .some(.center):
                    title = NSLocalizedString("Middle Button", comment: "")
                case .some(.back):
                    title = NSLocalizedString("Back Button", comment: "")
                case .some(.forward):
                    title = NSLocalizedString("Forward Button", comment: "")
                default:
                    title = String(format: NSLocalizedString("Button %d", comment: ""), number)
                }
            case let .logitechControl(identity):
                title = identity.userVisibleName
            }
            return modifierPrefix.isEmpty ? title : "\(modifierPrefix) \(title)"
        }
        if let scroll = mapping.scroll {
            let title: String
            switch scroll {
            case .up:
                title = NSLocalizedString("Scroll Up", comment: "")
            case .down:
                title = NSLocalizedString("Scroll Down", comment: "")
            case .left:
                title = NSLocalizedString("Scroll Left", comment: "")
            case .right:
                title = NSLocalizedString("Scroll Right", comment: "")
            }
            return modifierPrefix.isEmpty ? title : "\(modifierPrefix) \(title)"
        }
        return NSLocalizedString("Record Button", comment: "")
    }

    private static func mappingModifierTitle(_ mapping: Scheme.Buttons.Mapping) -> String {
        let flags = mapping.modifierFlags
        let parts: [(Bool, String)] = [
            (flags.contains(.maskControl), "⌃"),
            (flags.contains(.maskAlternate), "⌥"),
            (flags.contains(.maskShift), "⇧"),
            (flags.contains(.maskCommand), "⌘")
        ]
        return parts.compactMap { $0.0 ? $0.1 : nil }.joined()
    }

    static func keyPressTitle(_ keys: [Key]) -> String {
        keys.isEmpty
            ? NSLocalizedString("Click to record", comment: "")
            : keys.map(\.description).joined()
    }

    static func keyPressBehaviorTitle(_ behavior: Scheme.Buttons.Mapping.KeyPressBehavior) -> String {
        switch behavior {
        case .sendOnRelease:
            return NSLocalizedString("Send once on release", comment: "")
        case .repeat:
            return NSLocalizedString("Repeat", comment: "")
        case .holdWhilePressed:
            return NSLocalizedString("Hold keys while pressed", comment: "")
        }
    }

    static func keys(from modifierFlags: CGEventFlags) -> [Key] {
        var keys: [Key] = []

        if modifierFlags.contains(.maskControl) {
            keys
                .append(modifierFlags
                    .contains(.init(rawValue: UInt64(NX_DEVICERCTLKEYMASK))) ? .controlRight : .control)
        }
        if modifierFlags.contains(.maskShift) {
            keys.append(modifierFlags.contains(.init(rawValue: UInt64(NX_DEVICERSHIFTKEYMASK))) ? .shiftRight : .shift)
        }
        if modifierFlags.contains(.maskAlternate) {
            keys.append(modifierFlags.contains(.init(rawValue: UInt64(NX_DEVICERALTKEYMASK))) ? .optionRight : .option)
        }
        if modifierFlags.contains(.maskCommand) {
            keys
                .append(modifierFlags
                    .contains(.init(rawValue: UInt64(NX_DEVICERCMDKEYMASK))) ? .commandRight : .command)
        }

        return keys
    }

    static func orderedAutoScrollModes(_ modes: [Scheme.Buttons.AutoScroll.Mode]) -> [Scheme.Buttons.AutoScroll.Mode] {
        Scheme.Buttons.AutoScroll.Mode.allCases.filter { modes.contains($0) }
    }

    static func smoothedPresetTitle(_ preset: Scheme.Scrolling.Smoothed.Preset) -> String {
        switch preset {
        case .custom:
            return NSLocalizedString("Custom", comment: "")
        case .linear:
            return NSLocalizedString("Linear", comment: "")
        case .easeIn:
            return NSLocalizedString("Ease In", comment: "")
        case .easeOut:
            return NSLocalizedString("Ease Out", comment: "")
        case .easeInOut:
            return NSLocalizedString("Ease In Out", comment: "")
        case .quadratic:
            return NSLocalizedString("Quadratic", comment: "")
        case .cubic:
            return NSLocalizedString("Cubic", comment: "")
        case .quartic:
            return NSLocalizedString("Quartic", comment: "")
        case .easeOutCubic:
            return NSLocalizedString("Ease Out Cubic", comment: "")
        case .easeInOutCubic:
            return NSLocalizedString("Ease In Out Cubic", comment: "")
        case .easeOutQuartic:
            return NSLocalizedString("Ease Out Quartic", comment: "")
        case .easeInOutQuartic:
            return NSLocalizedString("Ease In Out Quartic", comment: "")
        case .smooth:
            return NSLocalizedString("Smooth", comment: "")
        }
    }

    static func gestureActionTitle(_ action: Scheme.Buttons.Gesture.GestureAction) -> String {
        switch action {
        case .none:
            return NSLocalizedString("None", comment: "")
        case .spaceLeft:
            return NSLocalizedString("Move left a space", comment: "")
        case .spaceRight:
            return NSLocalizedString("Move right a space", comment: "")
        case .missionControl:
            return NSLocalizedString("Mission Control", comment: "")
        case .appExpose:
            return NSLocalizedString("Application windows", comment: "")
        case .showDesktop:
            return NSLocalizedString("Show desktop", comment: "")
        case .launchpad:
            return NSLocalizedString("Launchpad", comment: "")
        }
    }

    static func doubleString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct RulesPrototypeRulePickerRowModel {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
}

private final class RulesPrototypeClosureButton: NSButton {
    private let closure: () -> Void

    init(title: String, symbol: String, action: @escaping () -> Void) {
        closure = action
        super.init(frame: .zero)
        self.title = title
        image = rpSymbolImage(symbol)
        imagePosition = .imageLeading
        bezelStyle = .rounded
        target = self
        self.action = #selector(runAction)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        closure()
    }
}

private final class RulesPrototypeRulePickerControl: NSControl {
    var onClick: (() -> Void)?

    private let iconContainer = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rpStyleLayer(
            self,
            cornerRadius: 10,
            background: RulesPrototypePalette.controlBackground.withAlphaComponent(0.62)
        )

        rpStyleLayer(
            iconContainer,
            cornerRadius: 7,
            background: RulesPrototypePalette.accent.withAlphaComponent(0.12)
        )
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.widthAnchor.constraint(equalToConstant: 28).isActive = true
        iconContainer.heightAnchor.constraint(equalToConstant: 28).isActive = true

        iconView.contentTintColor = RulesPrototypePalette.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15)
        ])

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let labels = rpVerticalStack(spacing: 2)
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(subtitleLabel)

        chevronView.image = rpSymbolImage("chevron.up.chevron.down")
        chevronView.contentTintColor = .tertiaryLabelColor
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let row = rpHorizontalStack(spacing: 10)
        row.addArrangedSubview(iconContainer)
        row.addArrangedSubview(labels)
        row.addArrangedSubview(rpFlexibleSpace())
        row.addArrangedSubview(chevronView)
        addSubview(row)
        rpPin(row, to: self, inset: NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String, symbol: String) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        iconView.image = rpSymbolImage(symbol)
    }

    override func mouseDown(with _: NSEvent) {
        isHighlighted = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        isHighlighted = false
        updateAppearance()
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isHighlighted
            ? RulesPrototypePalette.selection
            : RulesPrototypePalette.controlBackground.withAlphaComponent(0.62)).cgColor
    }
}

private final class RulesPrototypeSidebarHeadingCell: NSTableCellView {
    init(title: String) {
        super.init(frame: .zero)

        let label = rpLabel(title, size: 12, color: .secondaryLabelColor, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RulesPrototypeSidebarTableRowView: NSTableRowView {
    private let isHeading: Bool
    private var hovering = false

    init(isGroupRow: Bool) {
        isHeading = isGroupRow
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            needsDisplay = true
            syncContentSelection()
        }
    }

    override var isEmphasized: Bool {
        didSet {
            needsDisplay = true
            syncContentSelection()
        }
    }

    override func addSubview(_ view: NSView) {
        super.addSubview(view)
        syncContentSelection()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        guard !isHeading else {
            return
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
        super.mouseExited(with: event)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        guard !isHeading else {
            return
        }

        let rect = NSRect(x: 0, y: 2, width: bounds.width - 2, height: bounds.height - 4)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        if isSelected {
            RulesPrototypePalette.selection.setFill()
        } else if hovering {
            RulesPrototypePalette.controlBackground.withAlphaComponent(0.72).setFill()
        } else {
            return
        }
        path.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        drawBackground(in: dirtyRect)
    }

    private func syncContentSelection() {
        guard !isHeading else {
            return
        }
        for subview in subviews {
            (subview as? RulesPrototypeSidebarSectionCell)?.setRowSelected(isSelected)
        }
    }
}

private final class RulesPrototypeSidebarSectionCell: NSTableCellView {
    private let iconContainer = NSView()
    private let iconView: NSImageView
    private let titleLabel: NSTextField
    private let dotView: RulesPrototypeStatusDot?
    private var selectedSection: Bool

    init(title: String, symbol: String, selected: Bool, hasSettings: Bool) {
        selectedSection = selected
        iconView = NSImageView(image: rpSymbolImage(symbol) ?? NSImage())
        titleLabel = rpLabel(title, size: 13, color: .labelColor, weight: selected ? .semibold : .medium)
        dotView = hasSettings ? RulesPrototypeStatusDot() : nil
        super.init(frame: .zero)

        rpStyleLayer(
            iconContainer,
            cornerRadius: 7,
            background: selected ? RulesPrototypePalette.accent.withAlphaComponent(0.12) : NSColor.clear
        )
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.widthAnchor.constraint(equalToConstant: 26).isActive = true
        iconContainer.heightAnchor.constraint(equalToConstant: 26).isActive = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15)
        ])

        let row = rpHorizontalStack(spacing: 8)
        row.addArrangedSubview(iconContainer)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(rpFlexibleSpace())
        if let dotView {
            row.addArrangedSubview(dotView)
        }
        addSubview(row)
        rpPin(row, to: self, inset: NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10))
        updateColors()
    }

    func setRowSelected(_ selected: Bool) {
        selectedSection = selected
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateColors()
        }
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        updateColors()
    }

    private func updateColors() {
        let selected = selectedSection || ((superview as? NSTableRowView)?.isSelected ?? false)
        titleLabel.textColor = .labelColor
        iconView.contentTintColor = selected ? RulesPrototypePalette.accent : .labelColor
        iconContainer.layer?.backgroundColor = (selected
            ? RulesPrototypePalette.accent.withAlphaComponent(0.12)
            : NSColor.clear).cgColor
        dotView?.layer?.backgroundColor = RulesPrototypePalette.accent.cgColor
        dotView?.alphaValue = 1
    }
}

private final class RulesPrototypeInlineButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        isBordered = false
        bezelStyle = .regularSquare
        controlSize = .small
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .secondaryLabelColor
        setButtonType(.momentaryChange)
    }
}

private final class RulesPrototypeRulePickerRow: NSControl {
    var onClick: (() -> Void)?
    private let selected: Bool

    init(_ model: RulesPrototypeRulePickerRowModel) {
        selected = model.selected
        super.init(frame: .zero)
        rpStyleLayer(self, cornerRadius: 8)

        let imageView = NSImageView(image: rpSymbolImage(model.symbol) ?? NSImage())
        imageView.contentTintColor = selected ? RulesPrototypePalette.accent : .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let labels = rpVerticalStack(spacing: 1)
        labels.addArrangedSubview(rpLabel(model.title, size: 13, color: .labelColor, weight: .semibold))
        labels.addArrangedSubview(rpLabel(model.subtitle, size: 11, color: .secondaryLabelColor))

        let row = rpHorizontalStack(spacing: 9)
        row.addArrangedSubview(imageView)
        row.addArrangedSubview(labels)
        row.addArrangedSubview(rpFlexibleSpace())
        if selected {
            let check = NSImageView(image: rpSymbolImage("checkmark") ?? NSImage())
            check.contentTintColor = RulesPrototypePalette.accent
            row.addArrangedSubview(check)
        }

        addSubview(row)
        rpPin(row, to: self, inset: NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8))
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with _: NSEvent) {
        isHighlighted = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        isHighlighted = false
        updateAppearance()
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    private func updateAppearance() {
        if selected || isHighlighted {
            layer?.backgroundColor = RulesPrototypePalette.selection.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

private final class RulesPrototypeScrollEdgeEffectView: NSVisualEffectView {
    enum Edge {
        case top
        case bottom
    }

    private let edge: Edge
    private let gradientMask = CAGradientLayer()

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.mask = gradientMask
        updateMask()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradientMask.frame = bounds
        updateMask()
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    private func updateMask() {
        switch edge {
        case .top:
            gradientMask.startPoint = CGPoint(x: 0.5, y: 1)
            gradientMask.endPoint = CGPoint(x: 0.5, y: 0)
        case .bottom:
            gradientMask.startPoint = CGPoint(x: 0.5, y: 0)
            gradientMask.endPoint = CGPoint(x: 0.5, y: 1)
        }
        gradientMask.colors = [
            NSColor.black.withAlphaComponent(0.92).cgColor,
            NSColor.black.withAlphaComponent(0).cgColor
        ]
        gradientMask.locations = [0, 1]
    }
}

private class RulesPrototypeCanvasView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
        super.mouseDown(with: event)
    }
}

private final class RulesPrototypeFlippedView: RulesPrototypeCanvasView {
    override var isFlipped: Bool {
        true
    }
}

private final class RulesPrototypeCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rpStyleLayer(
            self,
            cornerRadius: 14,
            background: RulesPrototypePalette.cardBackground,
            border: RulesPrototypePalette.cardBorder,
            borderWidth: 1
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RulesPrototypeDivider: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = RulesPrototypePalette.separator.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RulesPrototypeSidebarRow: NSControl {
    var onClick: (() -> Void)?
    private let selected: Bool
    private let hasSettings: Bool

    init(title: String, symbol: String, selected: Bool, hasSettings: Bool) {
        self.selected = selected
        self.hasSettings = hasSettings
        super.init(frame: .zero)
        rpStyleLayer(self, cornerRadius: 9)

        let icon = NSImageView(image: rpSymbolImage(symbol) ?? NSImage())
        icon.contentTintColor = selected ? RulesPrototypePalette.accent : .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let label = rpLabel(
            title,
            size: 13,
            color: .labelColor,
            weight: selected ? .semibold : .medium
        )
        label.alphaValue = hasSettings || selected ? 1 : 0.9
        icon.alphaValue = hasSettings || selected ? 1 : 0.9

        let row = rpHorizontalStack(spacing: 8)
        row.addArrangedSubview(icon)
        row.addArrangedSubview(label)
        row.addArrangedSubview(rpFlexibleSpace())
        if hasSettings {
            row.addArrangedSubview(RulesPrototypeStatusDot())
        }
        addSubview(row)
        rpPin(row, to: self, inset: NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8))
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with _: NSEvent) {
        isHighlighted = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        isHighlighted = false
        updateAppearance()
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    private func updateAppearance() {
        if selected {
            layer?.backgroundColor = RulesPrototypePalette.selection.cgColor
        } else if isHighlighted {
            layer?.backgroundColor = RulesPrototypePalette.controlBackground.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

private final class RulesPrototypeIconView: NSView {
    init(symbol: String, accent: Bool, compact: Bool = false) {
        super.init(frame: .zero)
        rpStyleLayer(
            self,
            cornerRadius: compact ? 7 : 9,
            background: accent ? RulesPrototypePalette.accent.withAlphaComponent(0.14) : RulesPrototypePalette
                .controlBackground
        )
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: compact ? 28 : 34).isActive = true
        heightAnchor.constraint(equalToConstant: compact ? 28 : 34).isActive = true

        let imageView = NSImageView()
        imageView.image = rpSymbolImage(symbol)
        imageView.contentTintColor = accent ? RulesPrototypePalette.accent : .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: compact ? 15 : 18),
            imageView.heightAnchor.constraint(equalToConstant: compact ? 15 : 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RulesPrototypeStatusDot: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rpStyleLayer(self, cornerRadius: 3, background: RulesPrototypePalette.accent)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 6).isActive = true
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RulesPrototypePill: NSTextField {
    init(text: String, accent: Bool) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isBordered = false
        drawsBackground = false
        font = .systemFont(ofSize: 11, weight: .medium)
        textColor = accent ? RulesPrototypePalette.accent : .secondaryLabelColor
        alignment = .center
        rpStyleLayer(
            self,
            cornerRadius: 6,
            background: accent ? RulesPrototypePalette.accent.withAlphaComponent(0.12) : RulesPrototypePalette
                .controlBackground
        )
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RulesPrototypePaddedTextFieldCell: NSTextFieldCell {
    private let horizontalInset: CGFloat = 8

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(forBounds: super.drawingRect(forBounds: rect))
    }

    private func centeredTextRect(forBounds rect: NSRect) -> NSRect {
        let insetRect = rect.insetBy(dx: horizontalInset, dy: 0)
        let preferredHeight = min(cellSize(forBounds: insetRect).height, insetRect.height)
        let yOffset = max(0, floor((insetRect.height - preferredHeight) / 2))
        return NSRect(
            x: insetRect.minX,
            y: insetRect.minY + yOffset,
            width: insetRect.width,
            height: preferredHeight
        )
    }

    override func edit(
        withFrame cellFrame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredTextRect(forBounds: cellFrame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame cellFrame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredTextRect(forBounds: cellFrame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

private enum RulesPrototypePalette {
    static let accent = NSColor.controlAccentColor
    static let windowBackground = NSColor.windowBackgroundColor
    static let sidebarBackground = NSColor.controlBackgroundColor
    static let cardBackground = NSColor.controlBackgroundColor.withAlphaComponent(0.46)
    static let controlBackground = NSColor.controlBackgroundColor.withAlphaComponent(0.86)
    static let inputBackground = NSColor.textBackgroundColor.withAlphaComponent(0.86)
    static let selection = accent.withAlphaComponent(0.12)
    static let separator = NSColor.separatorColor.withAlphaComponent(0.10)
    static let cardBorder = NSColor.separatorColor.withAlphaComponent(0.10)
}

private func rpStyleLayer(
    _ view: NSView,
    cornerRadius: CGFloat,
    background: NSColor? = nil,
    border: NSColor? = nil,
    borderWidth: CGFloat = 0
) {
    view.wantsLayer = true
    guard let layer = view.layer else {
        return
    }
    layer.cornerRadius = cornerRadius
    layer.masksToBounds = true
    layer.allowsEdgeAntialiasing = true
    if #available(macOS 10.15, *) {
        layer.cornerCurve = .continuous
    }
    if let background {
        layer.backgroundColor = background.cgColor
    }
    if let border {
        layer.borderColor = border.cgColor
    }
    layer.borderWidth = borderWidth
}

private func rpStyleInputField(_ field: NSTextField) {
    let value = field.stringValue
    let alignment = field.alignment
    let font = field.font ?? .systemFont(ofSize: 13, weight: .regular)
    let cell = RulesPrototypePaddedTextFieldCell(textCell: value)
    cell.alignment = alignment
    cell.font = font
    cell.isEditable = true
    cell.isSelectable = true
    cell.isScrollable = true
    cell.usesSingleLineMode = true
    cell.lineBreakMode = .byTruncatingTail
    cell.isBordered = false
    cell.drawsBackground = false
    field.cell = cell
    field.stringValue = value
    field.alignment = alignment
    field.isBezeled = false
    field.isBordered = false
    field.drawsBackground = true
    field.backgroundColor = RulesPrototypePalette.inputBackground
    field.font = font
    rpStyleLayer(
        field,
        cornerRadius: 7,
        background: RulesPrototypePalette.inputBackground,
        border: RulesPrototypePalette.cardBorder,
        borderWidth: 1
    )
    field.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
}

private func rpStylePopup(_ popup: NSPopUpButton) {
    popup.controlSize = .regular
    popup.bezelStyle = .rounded
    popup.font = .systemFont(ofSize: 13, weight: .medium)
}

private func rpStyleActionButton(_ button: NSButton) {
    button.controlSize = .regular
    button.bezelStyle = .rounded
    button.font = .systemFont(ofSize: 13, weight: .medium)
}

private func rpVerticalStack(spacing: CGFloat) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

private func rpHorizontalStack(spacing: CGFloat) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

private func rpLabel(
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

private func rpPlainSymbolView(_ symbol: String, color: NSColor) -> NSImageView {
    let imageView = NSImageView(image: rpSymbolImage(symbol) ?? NSImage())
    imageView.contentTintColor = color
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.widthAnchor.constraint(equalToConstant: 22).isActive = true
    imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true
    return imageView
}

private func rpFlexibleSpace() -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
}

private func makeInsetDivider(width: CGFloat, leading: CGFloat) -> NSView {
    let wrapper = NSView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false
    wrapper.widthAnchor.constraint(equalToConstant: width).isActive = true
    wrapper.heightAnchor.constraint(equalToConstant: 1).isActive = true

    let divider = RulesPrototypeDivider()
    divider.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(divider)
    NSLayoutConstraint.activate([
        divider.topAnchor.constraint(equalTo: wrapper.topAnchor),
        divider.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: leading),
        divider.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
        divider.heightAnchor.constraint(equalToConstant: 1)
    ])
    return wrapper
}

private func rpPin(
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

private func rpRemoveArrangedSubviews(from stack: NSStackView) {
    for view in stack.arrangedSubviews {
        stack.removeArrangedSubview(view)
        view.removeFromSuperview()
    }
}

private func rpSymbolImage(_ name: String) -> NSImage? {
    if #available(macOS 11.0, *) {
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
    return nil
}

private func restartEventTap() {
    GlobalEventTap.shared.stop()
    GlobalEventTap.shared.start()
}

private extension Scheme.If {
    var prototypeIsEmpty: Bool {
        device == nil &&
            app == nil &&
            parentApp == nil &&
            groupApp == nil &&
            processName == nil &&
            processPath == nil &&
            display == nil
    }

    var onlyHasDeviceCondition: Bool {
        device != nil &&
            app == nil &&
            parentApp == nil &&
            groupApp == nil &&
            processName == nil &&
            processPath == nil &&
            display == nil
    }
}

private extension Array where Element == Scheme.If {
    var singlePrototypeCondition: Scheme.If? {
        count == 1 ? first : nil
    }
}

private extension Scheme {
    mutating func removeEmptyPrototypeSections() {
        $scrolling?.removeEmptyPrototypeSections()
        $buttons?.removeEmptyPrototypeSections()
        if $pointer?.prototypeIsEmpty == true {
            $pointer = nil
        }
        if $scrolling?.prototypeIsEmpty == true {
            $scrolling = nil
        }
        if $buttons?.prototypeIsEmpty == true {
            $buttons = nil
        }
    }
}

private extension Scheme.Pointer {
    var prototypeIsEmpty: Bool {
        acceleration == nil &&
            speed == nil &&
            disableAcceleration == nil &&
            redirectsToScroll == nil
    }
}

private extension Scheme.Scrolling {
    mutating func removeEmptyPrototypeSections() {
        if $reverse?.prototypeIsEmpty == true {
            $reverse = nil
        }
        if $distance?.prototypeIsEmpty == true {
            $distance = nil
        }
        if $acceleration?.prototypeIsEmpty == true {
            $acceleration = nil
        }
        if $speed?.prototypeIsEmpty == true {
            $speed = nil
        }
        if $smoothed?.prototypeIsEmpty == true {
            $smoothed = nil
        }
        if $modifiers?.prototypeIsEmpty == true {
            $modifiers = nil
        }
    }

    var prototypeIsEmpty: Bool {
        $reverse == nil &&
            $distance == nil &&
            $acceleration == nil &&
            $speed == nil &&
            $smoothed == nil &&
            $modifiers == nil
    }
}

private extension Scheme.Scrolling.Bidirectional {
    var prototypeIsEmpty: Bool {
        vertical == nil && horizontal == nil
    }
}

private extension Scheme.Buttons {
    mutating func removeEmptyPrototypeSections() {
        if $clickDebouncing?.prototypeIsEmpty == true {
            $clickDebouncing = nil
        }
        if $autoScroll?.prototypeIsEmpty == true {
            $autoScroll = nil
        }
        if $gesture?.prototypeIsEmpty == true {
            $gesture = nil
        }
    }

    var prototypeIsEmpty: Bool {
        (mappings?.isEmpty ?? true) &&
            universalBackForward == nil &&
            switchPrimaryButtonAndSecondaryButtons == nil &&
            $clickDebouncing == nil &&
            $autoScroll == nil &&
            $gesture == nil
    }
}

private extension Scheme.Buttons.ClickDebouncing {
    var prototypeIsEmpty: Bool {
        timeout == nil &&
            resetTimerOnMouseUp == nil &&
            buttons == nil
    }
}

private extension Scheme.Buttons.AutoScroll {
    var prototypeHasOptions: Bool {
        modes != nil ||
            speed != nil ||
            preserveNativeMiddleClick != nil ||
            trigger != nil
    }

    var prototypeIsEmpty: Bool {
        enabled == nil &&
            modes == nil &&
            speed == nil &&
            preserveNativeMiddleClick == nil &&
            trigger == nil
    }
}

private extension Scheme.Buttons.Gesture {
    var prototypeHasOptions: Bool {
        trigger != nil ||
            threshold != nil ||
            deadZone != nil ||
            cooldownMs != nil ||
            $actions != nil
    }

    var prototypeIsEmpty: Bool {
        enabled == nil &&
            trigger == nil &&
            threshold == nil &&
            deadZone == nil &&
            cooldownMs == nil &&
            $actions == nil
    }
}
