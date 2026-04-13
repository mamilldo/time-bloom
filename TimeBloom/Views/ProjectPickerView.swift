//
//  ProjectPickerView.swift
//  TimeBloom
//
//  Sheet that lets the user pick a project, then (optionally) one of its
//  tasks. Reused for both "start" and "switch" — only the title and the
//  action that fires on confirm differ.
//
//  Note: the API does not expose a way to *create* a task, so this view
//  only ever lets the user pick from existing ones. The README calls
//  this out so users know to add tasks via the web app.
//

import SwiftUI

struct ProjectPickerView: View {

    enum Mode {
        case start          // start a fresh timer
        case switchTask     // switch the active timer's project/task
    }

    let store: TimerStore
    let mode: Mode
    let onDismiss: () -> Void

    @State private var selectedProject: Project?
    @State private var selectedTask: TaskItem?
    @State private var search = ""

    private var filteredProjects: [Project] {
        guard !search.isEmpty else { return store.projects }
        return store.projects.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.client.localizedCaseInsensitiveContains(search) ||
            $0.tasks.contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Title bar
            HStack {
                Text(mode == .start ? "Start Timer" : "Switch Task")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(12)

            Divider()

            // Search
            TextField("Search projects or tasks", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Project / task list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredProjects) { project in
                        ProjectRow(
                            project: project,
                            selectedProject: $selectedProject,
                            selectedTask: $selectedTask
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 280)

            Divider()

            // Confirm bar
            HStack {
                if let p = selectedProject {
                    Text(p.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let t = selectedTask {
                        Text("›").foregroundStyle(.secondary)
                        Text(t.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button(mode == .start ? "Start" : "Switch") {
                    Task {
                        guard let project = selectedProject else { return }
                        switch mode {
                        case .start:
                            await store.start(projectId: project.id, taskId: selectedTask?.id)
                        case .switchTask:
                            await store.switchTo(projectId: project.id, taskId: selectedTask?.id)
                        }
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .disabled(selectedProject == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: Theme.popoverWidth, height: 420)
        .task {
            // If projects haven't been loaded yet (very first open), do
            // it now so the list isn't empty.
            if store.projects.isEmpty {
                await store.refreshProjects()
            }
        }
    }
}

// MARK: - Row

private struct ProjectRow: View {
    let project: Project
    @Binding var selectedProject: Project?
    @Binding var selectedTask: TaskItem?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded && selectedProject == project {
                    expanded.toggle()
                } else {
                    expanded = true
                    selectedProject = project
                    // Reset task selection when changing project.
                    if selectedTask.map({ t in !project.tasks.contains(t) }) ?? false {
                        selectedTask = nil
                    }
                }
            } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name)
                            .foregroundStyle(.primary)
                        Text(project.client)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedProject == project && selectedTask == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.brand)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                selectedProject == project
                    ? Theme.brand.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )

            if expanded {
                ForEach(project.tasks) { task in
                    Button {
                        selectedProject = project
                        selectedTask = task
                    } label: {
                        HStack {
                            Text(task.name).foregroundStyle(.primary)
                            Spacer()
                            if selectedTask == task {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.leading, 32)
                        .padding(.trailing, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        selectedTask == task
                            ? Theme.brand.opacity(0.10)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                }
                if project.tasks.isEmpty {
                    Text("No tasks for this project")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                        .padding(.vertical, 4)
                }
            }
        }
    }
}
