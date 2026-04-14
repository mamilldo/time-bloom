//
//  IdleAlertView.swift
//  TimeBloom
//
//  The dialog that appears when `IdleMonitor` reports the user has been
//  idle past their threshold. Four options:
//
//      • Keep      — count the idle minutes as work time (no API call)
//      • Add as new entry — stop timer, create a manual entry for the
//        idle period on a different project/task
//      • Switch    — opens the project picker to switch tasks
//      • Stop now  — POST stop
//

import SwiftUI

struct IdleAlertView: View {

    let event: IdleEvent
    let store: TimerStore
    let onClose: () -> Void

    @State private var showingPicker = false
    @State private var showingEntryForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.orange)
                Text("Are you still working?").font(.headline)
            }

            Text("Your timer for **\(event.timer.project)** has been running while you were away. You've been idle for **\(idleMinutes) minutes**.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button("Keep working") {
                    Task {
                        await store.resolveIdle(.keep)
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("Add idle time as new entry…") {
                    showingEntryForm = true
                }

                Button("Switch task…") {
                    showingPicker = true
                }

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
        .frame(width: 380)
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
        .sheet(isPresented: $showingEntryForm) {
            IdleEntryFormView(
                event: event,
                store: store,
                onDismiss: {
                    showingEntryForm = false
                    onClose()
                }
            )
        }
    }

    private var idleMinutes: Int { Int(event.idleSeconds / 60) }
}

/// A simplified form specifically for creating a manual entry from idle time.
/// Pre-fills the start/end time based on the idle period.
private struct IdleEntryFormView: View {

    let event: IdleEvent
    let store: TimerStore
    let onDismiss: () -> Void

    @State private var selectedProject: Project?
    @State private var selectedTask: TaskItem?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add idle time as entry").font(.headline)

            Text("This will stop the current timer and create a new entry for the idle period (\(timeRange)).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Project", selection: $selectedProject) {
                Text("Select a project…").tag(nil as Project?)
                ForEach(store.projects) { project in
                    Text("\(project.client) – \(project.name)").tag(project as Project?)
                }
            }

            if let project = selectedProject, !project.tasks.isEmpty {
                Picker("Task", selection: $selectedTask) {
                    Text("No task").tag(nil as TaskItem?)
                    ForEach(project.tasks) { task in
                        Text(task.name).tag(task as TaskItem?)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }
                Button("Create entry") {
                    Task {
                        guard let project = selectedProject else { return }
                        isSubmitting = true
                        await store.resolveIdle(.addAsNewEntry(
                            projectId: project.id,
                            taskId: selectedTask?.id,
                            startTime: event.idleStartedAt,
                            endTime: event.detectedAt
                        ))
                        isSubmitting = false
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .disabled(selectedProject == nil || isSubmitting)
            }
        }
        .padding(16)
        .frame(width: 340)
        .task {
            if store.projects.isEmpty {
                await store.refreshProjects()
            }
        }
    }

    private var timeRange: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "H:mm"
        return "\(fmt.string(from: event.idleStartedAt)) – \(fmt.string(from: event.detectedAt))"
    }
}
