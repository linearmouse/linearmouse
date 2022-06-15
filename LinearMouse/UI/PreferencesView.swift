//
//  PreferencesView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import Introspect
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        NavigationView {
            Sidebar()
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
