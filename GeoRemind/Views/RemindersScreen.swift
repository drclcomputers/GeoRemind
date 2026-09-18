import SwiftUI

struct RemindersScreen: View {
	@Binding var showingAdd: Bool

	@Environment(ReminderStore.self) private var reminders
	@Environment(GroupStore.self) private var groups
	@Environment(AppSettings.self) private var settings

	@State private var selectedPin: ReminderPin?
	@State private var showingSettings = false

	private var pins: [ReminderPin] { reminders.pins }

	var body: some View {
		ZStack(alignment: .bottomTrailing) {
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
						description: Text(
							"GeoReminders you add will show up here."
						)
					)
					.refreshable { await reminders.refresh() }
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
												Image(
													systemName: "person.2.fill"
												)
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

									Text(settings.formatDistance(pin.radius))
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
							.swipeActions(
								edge: .trailing,
								allowsFullSwipe: true
							) {
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
											pin.isActive
												? "Deactivate" : "Activate",
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
					.refreshable { await reminders.refresh() }
				}
			}

			Button {
				showingAdd = true
			} label: {
				Image(systemName: "plus")
					.font(.system(size: 22, weight: .semibold))
					.foregroundStyle(.white)
					.frame(width: 56, height: 56)
					.background(Color.accentColor, in: Circle())
					.shadow(color: .black.opacity(0.25), radius: 6, y: 3)
			}
			.padding(20)
			.accessibilityLabel("Add Reminder")
		}
		.navigationTitle("GeoReminders")
		.settingsAccess(isPresented: $showingSettings)
		.sheet(item: $selectedPin) { pin in
			PinDetailSheet(pinId: pin.id)
		}
		.task {
			await reminders.refresh()
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(15))
				guard !Task.isCancelled else { break }
				await reminders.refresh()
			}
		}
	}
}

#Preview {
	NavigationStack {
		RemindersScreen(showingAdd: .constant(false))
	}
	.environment(ReminderStore.shared)
	.environment(GroupStore.shared)
	.environment(AppSettings.shared)
}
