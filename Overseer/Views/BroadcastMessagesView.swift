//
//  BroadcastMessagesView.swift
//  Overseer
//
//  Admin-authored chat broadcasts, each repeating on its own interval
//  via vanilla `/say` (see BroadcastMessage / BroadcastScheduler /
//  RCONAutomationCoordinator.checkDueBroadcasts). Add as many as you
//  like; each has its own on/off switch, interval, and a manual
//  "Send Now".
//

import SwiftUI
import SwiftData

struct BroadcastMessagesView: View {
    @Query(sort: \BroadcastMessage.createdAt) private var messages: [BroadcastMessage]
    @Environment(\.modelContext) private var modelContext
    var rconCoordinator: RCONAutomationCoordinator

    @State private var newMessageText = ""
    @State private var newIntervalMinutes: Double = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addForm
            Divider()
            if messages.isEmpty {
                ContentUnavailableView(
                    "No Broadcast Messages",
                    systemImage: "megaphone",
                    description: Text("Add a message above to start repeating it on a schedule via vanilla /say.")
                )
            } else {
                List {
                    ForEach(messages) { message in
                        row(for: message)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .navigationTitle("Broadcasts")
    }

    // MARK: - Add form

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Broadcast").font(.headline)
            HStack(spacing: 10) {
                TextField("Message text (sent via vanilla /say)", text: $newMessageText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addMessage)
                Stepper(value: $newIntervalMinutes, in: 1...1440, step: 1) {
                    Text("Every \(Int(newIntervalMinutes))m")
                }
                .frame(width: 170)
                Button("Add") { addMessage() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addMessage() {
        let trimmed = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(BroadcastMessage(text: trimmed, intervalMinutes: newIntervalMinutes))
        try? modelContext.save()
        newMessageText = ""
        newIntervalMinutes = 15
    }

    // MARK: - Row

    private func row(for message: BroadcastMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .strikethrough(!message.isEnabled)
                    .foregroundStyle(message.isEnabled ? .primary : .secondary)
                HStack(spacing: 10) {
                    Label("Every \(Int(message.intervalMinutes))m", systemImage: "repeat")
                    if let lastSentAt = message.lastSentAt {
                        Text("Last sent \(lastSentAt, format: .relative(presentation: .named))")
                    } else {
                        Text("Not sent yet")
                    }
                    if let nextFireDate = BroadcastScheduler.nextFireDate(message) {
                        Text("Next \(nextFireDate, format: .relative(presentation: .named))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await rconCoordinator.sendBroadcastNow(message) }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(.borderless)
            .help("Send now")
            Toggle(
                "",
                isOn: Binding(
                    get: { message.isEnabled },
                    set: { message.isEnabled = $0; try? modelContext.save() }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            Button(role: .destructive) {
                delete(message)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
        .padding(.vertical, 4)
    }

    private func delete(_ message: BroadcastMessage) {
        modelContext.delete(message)
        try? modelContext.save()
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(messages[index])
        }
        try? modelContext.save()
    }
}
