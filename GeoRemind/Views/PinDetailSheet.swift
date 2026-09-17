//
//  PinDetailSheet.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 15/09/2026.
//

import MapKit
import SwiftData
import SwiftUI

struct PinDetailSheet: View {
	@Bindable var pin: ReminderPin
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss

	@State private var isEditing = false
	@State private var editedTitle = ""
	@State private var editedDesc = ""
	@State private var editedRadius: Double = 200
	@State private var editedNotifyMode: NotifyMode = .arrival
	@State private var showingDeleteConfirm = false

	@FocusState private var focusedField: Field?

	private enum Field {
		case title, description
	}

	private var displayRadius: Double {
		isEditing ? editedRadius : pin.radius
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					Map(
						position: .constant(
							.region(
								MKCoordinateRegion(
									center: pin.coordinate,
									latitudinalMeters: max(
										displayRadius * 4,
										500
									),
									longitudinalMeters: max(
										displayRadius * 4,
										500
									)
								)
							)
						)
					) {
						Marker(pin.title, coordinate: pin.coordinate)
						MapCircle(center: pin.coordinate, radius: displayRadius)
							.foregroundStyle(Color.accentColor.opacity(0.15))
							.stroke(Color.accentColor, lineWidth: 1)
					}
					.frame(height: 180)
					.clipShape(RoundedRectangle(cornerRadius: 12))
					.disabled(true)
					.listRowInsets(EdgeInsets())
					.animation(.easeInOut(duration: 0.2), value: editedRadius)
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
					Toggle("Active", isOn: $pin.isActive)
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
						LabeledContent("Radius", value: "\(Int(pin.radius))m")
					}
				}

				Section("Notify me on") {
					if isEditing {
						Picker("Notify me on", selection: $editedNotifyMode) {
							ForEach(NotifyMode.allCases) { mode in
								Text(mode.rawValue).tag(mode)
							}
						}
						.pickerStyle(.segmented)
					} else {
						LabeledContent(
							"Notify me on",
							value: NotifyMode.from(
								entry: pin.notifyOnEntry,
								exit: pin.notifyOnExit
							).rawValue
						)
					}
				}

				Section {
					Button("Delete GeoReminder", role: .destructive) {
						showingDeleteConfirm = true
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.dismissesKeyboardOnTap()
			.navigationTitle(pin.title.isEmpty ? "Reminder" : pin.title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(isEditing ? "Cancel" : "Done") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(isEditing ? "Save" : "Edit") {
						if isEditing {
							pin.title = editedTitle
							pin.desc = editedDesc
							pin.radius = editedRadius
							let flags = editedNotifyMode.flags
							pin.notifyOnEntry = flags.entry
							pin.notifyOnExit = flags.exit
						} else {
							editedTitle = pin.title
							editedDesc = pin.desc
							editedRadius = pin.radius
							editedNotifyMode = NotifyMode.from(
								entry: pin.notifyOnEntry,
								exit: pin.notifyOnExit
							)
						}
						isEditing.toggle()
					}
				}
			}
			.confirmationDialog(
				"Delete this GeoReminder?",
				isPresented: $showingDeleteConfirm,
				titleVisibility: .visible
			) {
				Button("Delete", role: .destructive) {
					context.delete(pin)
					dismiss()
				}
				Button("Cancel", role: .cancel) {}
			}
		}
	}
}
