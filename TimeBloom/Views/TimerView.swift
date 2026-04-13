//
//  TimerView.swift
//  TimeBloom
//
//  Main popover content shown when signed in. Two visual states:
//
//      ● Running    — green dot, project name, live HH:MM:SS, Stop + Switch
//      ○ Stopped    — "Start a timer" CTA that opens the project picker
//
//  All state comes from `TimerStore` (running status, projects, busy
//  flag, error). The view itself is otherwise stateless.
//

import SwiftUI

struct TimerView: View {

    let auth: AuthService
    let store: TimerStore

    @State private var showingPicker = false
    @State private var pickerMode: ProjectPickerView.Mode = .start

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch store.status {
            case .none:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)

            case .some(.stopped):
                stoppedBody

            case .some(.running(let timer)):
                runningBody(timer)
            }

            if let error = store.lastError {
                ErrorBanner(message: error.userMessage) {
                    store.lastError = nil
                }
            }

            Divider()

            footer
        }
        .padding(14)
        .frame(width: Theme.popoverWidth)
        .task {
            // Each time the popover opens we refresh both status and the
            // project list — cheap, and keeps the picker fresh.
            await store.refresh()
            await store.refreshProjects()
        }
        .sheet(isPresented: $showingPicker) {
            ProjectPickerView(
                store: store,
                mode: pickerMode,
                onDismiss: { showingPicker = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "leaf.fill").foregroundStyle(Theme.brand)
            Text("TimeBloom").font(.headline)
            Spacer()
            if store.isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Stopped

    private var stoppedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No timer running")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                pickerMode = .start
                showingPicker = true
            } label: {
                Label("Start a timer", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
            .keyboardShortcut("s", modifiers: [.command])
        }
    }

    // MARK: - Running

    private func runningBody(_ timer: RunningTimer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.runningIndicator)
                    .frame(width: 8, height: 8)
                Text(timer.project)
                    .font(.headline)
                    .lineLimit(1)
            }
            if let task = timer.task, !task.isEmpty {
                Text(task)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Live elapsed — recomputed via `store.now`.
            Text(elapsedString(start: timer.startTime, now: store.now))
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .padding(.vertical, 2)

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    Task { await store.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.isBusy)
                .keyboardShortcut("s", modifiers: [.command])

                Button {
                    pickerMode = .switchTask
                    showingPicker = true
                } label: {
                    Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.isBusy)
                .keyboardShortcut("w", modifiers: [.command])
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let user = auth.currentUser?.email {
                Text(user).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Refresh now") { Task { await store.refresh() } }
                Divider()
                Button("Sign out") { auth.signOut() }
                Divider()
                Button("Quit TimeBloom") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Helpers

    private func elapsedString(start: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Tiny error banner

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
