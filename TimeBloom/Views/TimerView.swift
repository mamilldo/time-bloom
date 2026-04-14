//
//  TimerView.swift
//  TimeBloom
//
//  Main popover content shown when signed in. Harvest-style layout:
//
//      ┌─────────────────────────┐
//      │ Today, 14 Apr   total ▸ │  ← date header + daily total
//      ├─────────────────────────┤
//      │  Acme Corp              │
//      │  Website Redesign       │  ← scrollable entries list
//      │  Development            │
//      │  9:07 – 9:48    0:41 ▸ │
//      │  ·····                  │
//      ├─────────────────────────┤
//      │ ● Running: Connect 0:27 │  ← active timer bar (if running)
//      │  [Stop]  [Switch]       │
//      ├─────────────────────────┤
//      │  user@email   + ⋯      │  ← footer with add + menu
//      └─────────────────────────┘
//

import SwiftUI

struct TimerView: View {

    let auth: AuthService
    let store: TimerStore

    @State private var showingPicker = false
    @State private var pickerMode: ProjectPickerView.Mode = .start
    @State private var showingEntryForm = false
    @State private var entryFormMode: EntryFormView.Mode = .create
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateHeader
            Divider()
            entriesList
            if case .running(let timer) = store.status {
                Divider()
                activeTimerBar(timer)
            }
            if let error = store.lastError {
                ErrorBanner(message: error.userMessage) {
                    store.lastError = nil
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(width: Theme.popoverWidth)
        .task {
            await store.refresh()
            await store.refreshProjects()
            await store.refreshEntries()
        }
        .sheet(isPresented: $showingPicker) {
            ProjectPickerView(
                store: store,
                mode: pickerMode,
                onDismiss: { showingPicker = false }
            )
        }
        .sheet(isPresented: $showingEntryForm) {
            EntryFormView(
                mode: entryFormMode,
                store: store,
                onDismiss: { showingEntryForm = false }
            )
        }
    }

    // MARK: - Date header

    private var dateHeader: some View {
        HStack {
            Image(systemName: "leaf.fill").foregroundStyle(Theme.brand)
            Text(todayString)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(totalString)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if store.isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, d MMM"
        return fmt.string(from: Date())
    }

    private var totalString: String {
        let total = store.todayTotalMinutes
        // Add running timer's live elapsed if active
        var extra = 0
        if let timer = store.status?.runningTimer {
            extra = Int(store.now.timeIntervalSince(timer.startTime)) / 60
        }
        let mins = total + extra
        return String(format: "%d:%02d", mins / 60, mins % 60)
    }

    // MARK: - Entries list

    private var entriesList: some View {
        Group {
            if store.entries.isEmpty && store.status?.runningTimer == nil {
                VStack(spacing: 8) {
                    Text("No entries today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        pickerMode = .start
                        showingPicker = true
                    } label: {
                        Label("Start a timer", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(store.entries) { entry in
                            let isRunning = store.status?.runningTimer?.timerId == entry.id
                            EntryRowView(
                                entry: entry,
                                isRunning: isRunning,
                                store: store,
                                onEdit: {
                                    entryFormMode = .edit(entry)
                                    showingEntryForm = true
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 260)
            }
        }
    }

    // MARK: - Active timer bar

    private func activeTimerBar(_ timer: RunningTimer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.runningIndicator)
                    .frame(width: 8, height: 8)
                Text(timer.project)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let task = timer.task, !task.isEmpty {
                    Text("· \(task)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(elapsedString(start: timer.startTime, now: store.now))
                    .font(.system(.subheadline, design: .monospaced))
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    Task { await store.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .disabled(store.isBusy)

                Button {
                    pickerMode = .switchTask
                    showingPicker = true
                } label: {
                    Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isBusy)
            }
        }
        .padding(10)
        .background(Theme.brand.opacity(0.05))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let user = auth.currentUser?.email {
                Text(user).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()

            // "+" add manual entry
            Button {
                entryFormMode = .create
                showingEntryForm = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.brand)
            }
            .buttonStyle(.plain)
            .help("Add time entry")

            // Start timer (when no timer running)
            if store.status?.runningTimer == nil {
                Button {
                    pickerMode = .start
                    showingPicker = true
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.brand)
                }
                .buttonStyle(.plain)
                .help("Start timer")
            }

            // Options menu
            Menu {
                Button("Refresh now") { Task {
                    await store.refresh()
                    await store.refreshEntries()
                }}
                Button("Manage projects…") {
                    NSWorkspace.shared.open(URL(string: "https://time-bloom-suite.lovable.app/projects")!)
                }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
