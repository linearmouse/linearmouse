// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Introspect
import SwiftUI

struct Preferences: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        NavigationView {
            Sidebar()

            ScrollingSettings()
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        Preferences()
    }
}
