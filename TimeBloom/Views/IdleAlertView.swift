//
//  IdleAlertView.swift
//  TimeBloom
//
//  The dialog that appears when `IdleMonitor` reports the user has been
//  idle past their threshold. Three options:
//
//      • Keep      — count the idle minutes as work time (no API call)
//      • Stop now  — POST stop. The minutes between idle-start and now
//                    are still logged because the API doesn't accept a
//                    backdated stop time. We tell the user this honestly.
//      • Switch    — opens the project picker to switch tasks
//
//  Presented inside a borderless `NSWindow` so it floats above other
//  apps without needing the popover to be open.
//

import SwiftUI

struct IdleAlertView: View {

    let event: IdleEvent
    let store: TimerStore
    let onClose: () -> Void

    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.orange)
                Text("Are you still working?").font(.headline)
            }

            Text("Your timer for **\(event.timer.project)** has been running while you were away. You've been idle for **\(idleMinutes) minutes**.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Text("Tip: the API can only stop the timer at the current moment. Idle minutes are kept on whichever task is active when you stop or switch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 8) {
                Button("Keep working") {
                    Task {
                        await store.resolveIdle(.keep)
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("Switch task…") {
                    showingPicker = true
                }

                Spacer()

                Button(role: .destructive) {
                    Task {
                        await store.resolveIdle(.stop)
                        onClose()
                    }
                } label: {
                    Text("Stop timer")
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .sheet(isPresented: $showingPicker) {
            ProjectPickerView(
                store: store,
                mode: .switchTask,
                onDismiss: {
                    showingPicker = false
                    onClose()
                }
            )
        }
    }

    private var idleMinutes: Int {
        Int(event.idleSeconds / 60)
    }
}
