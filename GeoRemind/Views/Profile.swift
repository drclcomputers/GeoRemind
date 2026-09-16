//
//  Profile.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import SwiftData
import SwiftUI

struct Profile: View {
	@Query(sort: \ReminderPin.timestamp, order: .reverse) private var pins:
		[ReminderPin]
	@Environment(\.modelContext) private var context

	@State private var selectedPin: ReminderPin?

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
									Text(pin.title)
										.font(.headline)
										.foregroundStyle(.primary)
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
							Button(role: .destructive) {
								context.delete(pin)
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
						.swipeActions(edge: .leading) {
							Button {
								pin.isActive.toggle()
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
				.listStyle(.insetGrouped)
			}
		}
		.navigationTitle("GeoReminders")
		.sheet(item: $selectedPin) { pin in
			PinDetailSheet(pin: pin)
		}
	}
}

#Preview {
	NavigationStack {
		Profile()
	}
}
