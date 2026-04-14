//
//  EntryRowView.swift
//  TimeBloom
//
//  A single row in the Harvest-style entries list. Shows client, project,
//  task, time range, duration, and a play button to restart that task.
//

import SwiftUI

struct EntryRowView: View {

    let entry: TimeEntry
    let isRunning: Bool
    let store: TimerStore
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.project ?? "Unknown project")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let task = entry.task, !task.isEmpty {
                        Text(task)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(entry.timeRange)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(entry.durationFormatted)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)

                // Play button — restart this project/task as a new timer
                Button {
                    Task {
                        await store.start(projectId: entry.projectId, taskId: entry.taskId)
                    }
                } label: {
                    Image(systemName: isRunning ? "clock.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(isRunning ? Theme.runningIndicator : Theme.brand)
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .help(isRunning ? "Currently running" : "Start timer for this task")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isRunning ? Theme.brand.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
