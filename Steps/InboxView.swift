//
//  InboxView.swift
//  Steps
//
//  A simple history of everything the app has notified about — the same
//  title/body pairs posted as banners, newest first (see NotificationLog).
//  Gives the day's check-ins a home even when the banners were missed.
//  notes-plontsch styling: monospaced, flat, hierarchy from space + colour.
//

import SwiftUI

struct InboxView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [InboxMessage] = NotificationLog.all()

    private let textPrimary = Color("AppText")
    private let textMuted = Color("AppTextMuted")

    var body: some View {
        NavigationStack {
            Group {
                if messages.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color("AppBackground"))
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        // Opening the Inbox counts as reading everything in it.
        .onAppear { NotificationLog.markAllSeen() }
    }

    private var list: some View {
        List {
            ForEach(groupedMessages, id: \.day) { group in
                Section {
                    ForEach(group.items) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(message.title)
                                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(textPrimary)
                                Spacer(minLength: 8)
                                Text(message.date, format: .dateTime.hour().minute())
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(textMuted)
                            }
                            Text(message.body)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(textMuted)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color("AppBackground"))
                    }
                } header: {
                    Text(dayLabel(group.day))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(textMuted)
                        .textCase(nil)
                }
            }

            Section {
                Button(role: .destructive) {
                    NotificationLog.clear()
                    messages = []
                } label: {
                    Label("Clear inbox", systemImage: "trash")
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .listRowBackground(Color("AppBackground"))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// Messages bucketed by calendar day, newest day first.
    private var groupedMessages: [(day: Date, items: [InboxMessage])] {
        let cal = Calendar.current
        return Dictionary(grouping: messages) { cal.startOfDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(textMuted)
            Text("No messages yet")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(textPrimary)
            Text("Your step check-ins — milestones, streaks, and goal nudges — show up here as they're sent.")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    InboxView()
}
