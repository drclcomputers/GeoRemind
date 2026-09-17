//
//  RemindersScreen.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import SwiftUI

struct RemindersScreen: View {
	@Environment(ReminderStore.self) private var reminders
	@Environment(GroupStore.self) private var groups

	@State private var selectedPin: ReminderPin?

	private var pins: [ReminderPin] { reminders.pins }

	var body: some View {
		VStack(spacing: 0) {
			if GeofenceManager.shared.isOverRegionLimit {
				PermissionBanner(
					icon: "exclamationmark.triangle",
					message:
						"Only 20 active reminders can be monitored in the background. You have \(GeofenceManager.shared.totalActiveCount) active."
				)
			}
			if pins.isEmpty {
				ContentUnavailableView(
					"No GeoReminders",
					systemImage: "mappin.slash",
					description: Text("GeoReminders you add will show up here.")
				)
			} else {
				List {
					ForEach(pins) { pin in
						Button {
							selectedPin = pin
						} label: {
							HStack(spacing: 12) {
								Circle()
									.fill(
										pin.isActive
											? Color.accentColor : Color.gray
									)
									.frame(width: 10, height: 10)

								VStack(alignment: .leading, spacing: 2) {
									HStack(spacing: 6) {
										Text(pin.title)
											.font(.headline)
											.foregroundStyle(.primary)
										if pin.groupId != nil {
											Image(systemName: "person.2.fill")
												.font(.caption2)
												.foregroundStyle(.secondary)
										}
									}
									if !pin.desc.isEmpty {
										Text(pin.desc)
											.font(.subheadline)
											.foregroundStyle(.secondary)
											.lineLimit(1)
									}
								}

								Spacer()

								Text("\(Int(pin.radius)) m")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.swipeActions(edge: .trailing, allowsFullSwipe: true) {
							if pin.isOwnedByCurrentUser {
								Button(role: .destructive) {
									Task { await reminders.delete(pin) }
								} label: {
									Label("Delete", systemImage: "trash")
								}
							}
						}
						.swipeActions(edge: .leading) {
							if pin.isOwnedByCurrentUser {
								Button {
									Task {
										await reminders.setActive(
											pin,
											isActive: !pin.isActive
										)
									}
								} label: {
									Label(
										pin.isActive ? "Deactivate" : "Activate",
										systemImage: pin.isActive
											? "bell.slash" : "bell"
									)
								}
								.tint(pin.isActive ? .gray : .accentColor)
							}
						}
					}
				}
				.listStyle(.insetGrouped)
			}
		}
		.navigationTitle("GeoReminders")
		.sheet(item: $selectedPin) { pin in
			PinDetailSheet(pinId: pin.id)
		}
	}
}

#Preview {
	NavigationStack {
		RemindersScreen()
	}
	.environment(ReminderStore.shared)
	.environment(GroupStore.shared)
}
