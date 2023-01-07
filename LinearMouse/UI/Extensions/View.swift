// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Introspect
import SwiftUI

extension View {
    public func introspectSplitView(customize: @escaping (NSSplitView) -> Void) -> some View {
        introspect(selector: TargetViewSelector.ancestorOrSiblingOfType, customize: customize)
    }

    func sidebarThickness(min: CGFloat, max: CGFloat) -> some View {
        introspectSplitView { splitView in
            guard let item = (splitView.delegate as? NSSplitViewController)?.splitViewItems.first else { return }

            item.minimumThickness = min
            item.maximumThickness = max
        }
    }

    func preventSidebarCollapse() -> some View {
        introspectSplitView { splitView in
            (splitView.delegate as? NSSplitViewController)?.splitViewItems.first?.canCollapse = false
        }
    }
}
