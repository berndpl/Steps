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
                if !messages.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") {
                            NotificationLog.clear()
                            messages = []
                        }
                        .font(.system(.body, design: .monospaced))
                        .tint(textMuted)
                    }
                }
            }
        }
        // Opening the Inbox counts as reading everything in it.
        .onAppear { NotificationLog.markAllSeen() }
    }

    private var list: some View {
        List(messages) { message in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.title)
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    Spacer(minLength: 8)
                    Text(message.date, format: .dateTime.weekday().hour().minute())
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
