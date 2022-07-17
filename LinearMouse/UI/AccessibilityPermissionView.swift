// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import os.log
import SwiftUI

struct AccessibilityPermissionView: View {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AccessibilityPermissionView")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 15) {
                Image("AccessibilityIcon")

                Text("LinearMouse needs Accessibility permission")
                    .font(.headline)
            }
            .padding(.horizontal)

            Text(
                "You need to grant Accessibility permission in System Preferences > Security & Privacy > Accessibility."
            )
            .padding(.horizontal)

            HyperLink(URL(string: "https://go.linearmouse.org/accessibility-permission")!) {
                Text("Get more help")
            }
            .padding(.horizontal)

            Spacer()

            HStack {
                Button("Open Accessibility") {
                    openAccessibility()
                }
            }
        }
        .padding()
        .frame(width: 450, height: 200)
    }

    func openAccessibility() {
        do {
            try AccessibilityPermission.reset()
        } catch {}
        AccessibilityPermission.prompt()
        AccessibilityPermissionWindow.shared.moveAside()
    }
}

struct AccessibilityPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        AccessibilityPermissionView()
    }
}
