//
//  View.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/15.
//

import Introspect
import SwiftUI

extension View {
    public func introspectSplitView(customize: @escaping (NSSplitView) -> ()) -> some View {
        return introspect(selector: TargetViewSelector.ancestorOrSiblingOfType, customize: customize)
    }

    func sidebarThickness(min: CGFloat, max: CGFloat) -> some View {
        return introspectSplitView { splitView in
            guard let item = (splitView.delegate as? NSSplitViewController)?.splitViewItems.first else { return }

            item.minimumThickness = min
            item.maximumThickness = max
        }
    }

    func preventSidebarCollapse() -> some View {
        return introspectSplitView { splitView in
            (splitView.delegate as? NSSplitViewController)?.splitViewItems.first?.canCollapse = false
        }
    }
}
