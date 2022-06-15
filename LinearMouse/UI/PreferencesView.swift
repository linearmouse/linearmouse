// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

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
