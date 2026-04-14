//
//  EntryFormView.swift
//  TimeBloom
//
//  A sheet for creating or editing a time entry. Fields: project, task,
//  start time, end time, notes. Mirrors Harvest's "Edit Time Entry" dialog.
//

import SwiftUI

struct EntryFormView: View {

    enum Mode: Equatable {
        case create
        case edit(TimeEntry)
    }

    let mode: Mode
    let store: TimerStore
    let onDismiss: () -> Void

    // MARK: - Form state

    @State private var selectedProject: Project?
    @State private var selectedTask: TaskItem?
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var notes: String = ""
    @State private var isSubmitting = false

    private var isValid: Bool {
        selectedProject != nil && endTime > startTime
    }

    private var title: String {
        mode == .create ? "New Time Entry" : "Edit Time Entry"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Project picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project").font(.caption).foregroundStyle(.secondary)
                        Picker("Project", selection: $selectedProject) {
                            Text("Select a project…").tag(nil as Project?)
                            ForEach(store.projects) { project in
                                Text("\(project.client) – \(project.name)").tag(project as Project?)
                            }
                        }
                        .labelsHidden()
                    }

                    // Task picker (scoped to selected project)
                    if let project = selectedProject, !project.tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Task").font(.caption).foregroundStyle(.secondary)
                            Picker("Task", selection: $selectedTask) {
                                Text("No task").tag(nil as TaskItem?)
                                ForEach(project.tasks) { task in
                                    Text(task.name).tag(task as TaskItem?)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    // Time pickers
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start").font(.caption).foregroundStyle(.secondary)
                            DatePicker("", selection: $startTime, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                        }
                        Text("to")
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("End").font(.caption).foregroundStyle(.secondary)
                            DatePicker("", selection: $endTime, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                        }
                    }

                    // Duration display
                    if endTime > startTime {
                        let mins = Int(endTime.timeIntervalSince(startTime) / 60)
                        Text("Duration: \(mins / 60)h \(mins % 60)m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes (optional)").font(.caption).foregroundStyle(.secondary)
                        TextField("What did you work on?", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(12)
            }

            Divider()

            // Action bar
            HStack {
                if case .edit(let entry) = mode {
                    Button(role: .destructive) {
                        Task {
                            isSubmitting = true
                            await store.deleteEntry(timerId: entry.id)
                            isSubmitting = false
                            onDismiss()
                        }
                    } label: {
                        Text("Delete")
                    }
                }
                Spacer()
                Button("Cancel") { onDismiss() }
                Button(mode == .create ? "Create" : "Save") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .disabled(!isValid || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: Theme.popoverWidth, height: 400)
        .onAppear(perform: populateFromMode)
        .task {
            if store.projects.isEmpty {
                await store.refreshProjects()
            }
        }
    }

    // MARK: - Logic

    private func populateFromMode() {
        guard case .edit(let entry) = mode else { return }
        selectedProject = store.projects.first { $0.id == entry.projectId }
        selectedTask = selectedProject?.tasks.first { $0.id == entry.taskId }
        startTime = entry.startTime ?? Date()
        endTime = entry.endTime ?? Date()
        notes = entry.description ?? ""
    }

    private func submit() async {
        guard let project = selectedProject else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        switch mode {
        case .create:
            await store.createEntry(
                projectId: project.id,
                taskId: selectedTask?.id,
                startTime: startTime,
                endTime: endTime,
                description: notes.isEmpty ? nil : notes
            )
        case .edit(let entry):
            await store.editEntry(
                timerId: entry.id,
                projectId: project.id,
                taskId: selectedTask?.id,
                startTime: startTime,
                endTime: endTime,
                description: notes.isEmpty ? nil : notes
            )
        }
        onDismiss()
    }
}
