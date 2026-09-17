//
//  PinDetailSheet.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 15/09/2026.
//

import MapKit
import SwiftUI

struct PinDetailSheet: View {
	let pinId: UUID

	@Environment(ReminderStore.self) private var reminders
	@Environment(GroupStore.self) private var groups
	@Environment(AuthService.self) private var auth
	@Environment(\.dismiss) private var dismiss

	@State private var isEditing = false
	@State private var editedTitle = ""
	@State private var editedDesc = ""
	@State private var editedRadius: Double = 200
	@State private var editedNotifyMode: NotifyMode = .arrival
	@State private var editedGroupId: UUID?
	@State private var showingDeleteConfirm = false
	@State private var saveError: String?

	@FocusState private var focusedField: Field?

	private enum Field {
		case title, description
	}

	private var pin: ReminderPin? {
		reminders.pin(id: pinId)
	}

	private var displayRadius: Double {
		isEditing ? editedRadius : (pin?.radius ?? 200)
	}

	private var canEdit: Bool {
		pin?.isOwnedByCurrentUser == true
	}

	var body: some View {
		NavigationStack {
			if let pin {
				Form {
					Section {
						Map(
							position: .constant(
								.region(
									MKCoordinateRegion(
										center: pin.coordinate,
										latitudinalMeters: max(
											displayRadius * 3,
											200
										),
										longitudinalMeters: max(
											displayRadius * 3,
											200
										)
									)
								)
							)
						) {
							Marker(pin.title, coordinate: pin.coordinate)
							MapCircle(
								center: pin.coordinate,
								radius: displayRadius
							)
							.foregroundStyle(Color.accentColor.opacity(0.15))
							.stroke(Color.accentColor, lineWidth: 1)
						}
						.frame(height: 180)
						.clipShape(RoundedRectangle(cornerRadius: 12))
						.disabled(true)
						.listRowInsets(EdgeInsets())
						.animation(
							.easeInOut(duration: 0.2),
							value: editedRadius
						)
					}

					Section("Details") {
						if isEditing {
							TextField("Title", text: $editedTitle)
								.focused($focusedField, equals: .title)
							TextField(
								"Description",
								text: $editedDesc,
								axis: .vertical
							)
							.lineLimit(2...6)
							.focused($focusedField, equals: .description)
						} else {
							LabeledContent("Title", value: pin.title)
							if !pin.desc.isEmpty {
								LabeledContent("Description", value: pin.desc)
							}
						}
						if canEdit {
							Toggle(
								"Active",
								isOn: Binding(
									get: { pin.isActive },
									set: { newValue in
										Task {
											await reminders.setActive(
												pin,
												isActive: newValue
											)
										}
									}
								)
							)
						} else {
							LabeledContent(
								"Active",
								value: pin.isActive ? "Yes" : "No"
							)
						}
					}

					Section("Radius") {
						if isEditing {
							VStack(alignment: .leading, spacing: 8) {
								Text("\(Int(editedRadius)) m")
									.font(.subheadline.monospacedDigit())
									.foregroundStyle(.secondary)
								Slider(
									value: $editedRadius,
									in: 50...2000,
									step: 50
								)
							}
						} else {
							LabeledContent(
								"Radius",
								value: "\(Int(pin.radius))m"
							)
						}
					}

					Section("Notify me on") {
						if isEditing {
							Picker(
								"Notify me on",
								selection: $editedNotifyMode
							) {
								ForEach(NotifyMode.allCases) { mode in
									Text(mode.rawValue).tag(mode)
								}
							}
							.pickerStyle(.segmented)
						} else {
							LabeledContent(
								"Notify me on",
								value: pin.notifyMode.rawValue
							)
						}
					}

					if canEdit, auth.isAuthenticated, !groups.groups.isEmpty {
						Section("Share with") {
							if isEditing {
								Picker(
									"Share with",
									selection: $editedGroupId
								) {
									Text("Only me").tag(Optional<UUID>.none)
									ForEach(groups.groups) { group in
										Text(group.name).tag(Optional(group.id))
									}
								}
							} else if let groupId = pin.groupId,
								let group = groups.groups.first(where: {
									$0.id == groupId
								})
							{
								LabeledContent("Shared with", value: group.name)
							} else {
								LabeledContent("Shared with", value: "Only me")
							}
						}
					}

					if canEdit {
						Section {
							Button("Delete GeoReminder", role: .destructive) {
								showingDeleteConfirm = true
							}
						}
					}
				}
				.scrollDismissesKeyboard(.interactively)
				.dismissesKeyboardOnTap()
				.navigationTitle(pin.title.isEmpty ? "Reminder" : pin.title)
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button(isEditing ? "Cancel" : "Done") {
							if isEditing {
								isEditing = false
							} else {
								dismiss()
							}
						}
					}
					if canEdit {
						ToolbarItem(placement: .confirmationAction) {
							Button(isEditing ? "Save" : "Edit") {
								if isEditing {
									saveEdits(pin)
								} else {
									editedTitle = pin.title
									editedDesc = pin.desc
									editedRadius = pin.radius
									editedNotifyMode = pin.notifyMode
									editedGroupId = pin.groupId
									isEditing = true
								}
							}
						}
					}
				}
				.confirmationDialog(
					"Delete this GeoReminder?",
					isPresented: $showingDeleteConfirm,
					titleVisibility: .visible
				) {
					Button("Delete", role: .destructive) {
						Task {
							await reminders.delete(pin)
							dismiss()
						}
					}
					Button("Cancel", role: .cancel) {}
				}
				.alert(
					"Couldn't save",
					isPresented: Binding(
						get: { saveError != nil },
						set: { if !$0 { saveError = nil } }
					)
				) {
					Button("OK", role: .cancel) {}
				} message: {
					Text(saveError ?? "")
				}
			} else {
				ContentUnavailableView(
					"Reminder removed",
					systemImage: "mappin.slash"
				)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Done") { dismiss() }
					}
				}
			}
		}
	}

	private func saveEdits(_ pin: ReminderPin) {
		var next = pin
		next.title = editedTitle
		next.desc = editedDesc
		next.radius = editedRadius
		let flags = editedNotifyMode.flags
		next.notifyOnEntry = flags.entry
		next.notifyOnExit = flags.exit
		next.groupId = editedGroupId
		Task {
			do {
				try await reminders.update(next)
				isEditing = false
			} catch {
				saveError = error.localizedDescription
			}
		}
	}
}
