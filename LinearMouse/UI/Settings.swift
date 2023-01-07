// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Introspect
import SwiftUI

struct Settings: View {
    var body: some View {
        NavigationView {
            Sidebar()

            ScrollingSettings()
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Settings()
    }
}
