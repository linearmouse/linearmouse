// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import os.log
import SwiftUI

struct AccessibilityPermissionView: View {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AccessibilityPermissionView")

    @State var resetAllPermissionConfirmationShown = false

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

                Spacer()

                Button("Reset all permissions...") {
                    resetAllPermissions()
                }
            }
        }
        .padding()
        .frame(width: 450, height: 200)
    }

    func openAccessibility() {
        AccessibilityPermission.prompt()
        AccessibilityPermissionWindow.shared.moveAside()
    }

    func resetAllPermissions() {
        let alert = NSAlert()

        alert.messageText = NSLocalizedString("Are you sure?", comment: "")
        alert.informativeText = NSLocalizedString(
            "By doing this, the Accessibility permissions will be completely reset and all permissions—including those granted to other apps—will be removed.\n\nUnless the permissions are totally broken, you do not have to reset them.",
            comment: ""
        )
        alert.alertStyle = .warning

        let reset = alert.addButton(withTitle: NSLocalizedString("Reset", comment: ""))
        reset.keyEquivalent = ""
        if #available(macOS 11.0, *) {
            reset.hasDestructiveAction = true
        }

        let cancel = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancel.keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        guard (try? AccessibilityPermission.reset()) != nil else {
            return
        }

        openAccessibility()
    }
}

struct AccessibilityPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        AccessibilityPermissionView()
    }
}
