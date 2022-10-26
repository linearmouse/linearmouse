// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Introspect
import SwiftUI

struct Preferences: View {
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
