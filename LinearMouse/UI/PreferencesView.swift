//
//  PreferencesView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var defaults = AppDefaults.shared
    @State var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralView()
                .padding(.vertical, 20)
                .padding(.horizontal, 30)
                .tabItem { Text("General") }
                .tag(0)

            ScrollView {
                ModifierKeysView()
                    .padding(.vertical, 20)
                    .padding(.horizontal, 30)
            }
            .tabItem { Text("Modifier Keys") }
            .tag(1)
        }
        .padding(30)
        .frame(minWidth: 0,
               maxWidth: .infinity,
               minHeight: 0,
               maxHeight: .infinity,
               alignment: .topLeading)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView(selectedTab: 1)
    }
}
