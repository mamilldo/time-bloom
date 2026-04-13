//
//  PopoverRootView.swift
//  TimeBloom
//
//  The view hosted directly inside the menu bar's `NSPopover`. Its only
//  job is to switch between the login screen and the main timer UI based
//  on `auth.isSignedIn`. Both child views own their own state.
//

import SwiftUI

struct PopoverRootView: View {

    let auth: AuthService
    let store: TimerStore

    var body: some View {
        Group {
            if auth.isSignedIn {
                TimerView(auth: auth, store: store)
            } else {
                LoginView(auth: auth)
            }
        }
        // Match the system's popover material so the rounded corners
        // blend in with the chrome NSPopover draws around us.
        .background(.regularMaterial)
    }
}
