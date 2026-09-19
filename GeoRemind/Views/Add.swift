//
//  Add.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import CoreLocation
import MapKit
import SwiftUI

struct Add: View {
	@Environment(ReminderStore.self) private var reminders
	@Environment(GroupStore.self) private var groups
	@Environment(AuthService.self) private var auth
	@Environment(AppSettings.self) private var settings
	@Environment(\.dismiss) private var dismiss

	@State private var title = ""
	@State private var desc = ""
	@State private var radius: Double = 200
	@State private var notifyMode: NotifyMode = .arrival
	@State private var selectedCoordinate: CLLocationCoordinate2D?
	@State private var selectedAddress: String = ""
	@State private var selectedGroupId: UUID?
	@State private var showingSearch = false
	@State private var showingValidationAlert = false
	@State private var isLocating = false
	@State private var isSaving = false
	@State private var saveError: String?

	@FocusState private var focusedField: Field?

	private enum Field {
		case title, description
	}

	private var canSave: Bool {
		!title.trimmingCharacters(in: .whitespaces).isEmpty
			&& selectedCoordinate != nil
			&& !isSaving
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Title", text: $title)
						.focused($focusedField, equals: .title)
						.submitLabel(.next)
						.onSubmit { focusedField = .description }

					TextField("Description", text: $desc, axis: .vertical)
						.lineLimit(2...6)
						.focused($focusedField, equals: .description)
				}

				Section("Location") {
					if let coord = selectedCoordinate {
						Map(
							position: .constant(
								.region(
									MKCoordinateRegion(
										center: coord,
										latitudinalMeters: max(radius * 3, 200),
										longitudinalMeters: max(radius * 3, 200)
									)
								)
							)
						) {
							Marker(
								selectedAddress.isEmpty
									? "Selected Location" : selectedAddress,
								coordinate: coord
							)
							MapCircle(center: coord, radius: radius)
								.foregroundStyle(
									Color.accentColor.opacity(0.15)
								)
								.stroke(Color.accentColor, lineWidth: 1)
						}
						.frame(height: 160)
						.clipShape(RoundedRectangle(cornerRadius: 12))
						.disabled(true)
						.listRowInsets(EdgeInsets())
						.padding(.horizontal, 4)
						.padding(.vertical, 2)
						.animation(.easeInOut(duration: 0.2), value: radius)

						if !selectedAddress.isEmpty {
							Text(selectedAddress)
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
					}

					Button {
						isLocating = true
						GeofenceManager.shared.requestWhenInUseAuthorization()
						Task {
							selectedCoordinate = await getCurrentLocation()
							selectedAddress = ""
							isLocating = false
						}
					} label: {
						Label(
							isLocating ? "Locating…" : "Use Current Location",
							systemImage: "location.fill"
						)
					}
					.disabled(isLocating)

					Button {
						showingSearch = true
					} label: {
						Label(
							"Search for a Place",
							systemImage: "magnifyingglass"
						)
					}

					savedPlaceButton(.home)
					savedPlaceButton(.work)
				}

				if selectedCoordinate != nil {
					Section("Radius") {
						VStack(alignment: .leading, spacing: 8) {
							Text(settings.formatDistance(radius))
								.font(.subheadline.monospacedDigit())
								.foregroundStyle(.secondary)
							Slider(value: $radius, in: 50...2000, step: 50)
						}
					}

					Section("Notify me on") {
						Picker("Notify me on", selection: $notifyMode) {
							ForEach(NotifyMode.allCases) { mode in
								Text(mode.rawValue).tag(mode)
							}
						}
						.pickerStyle(.segmented)
					}
				}

				if auth.isAuthenticated {
					Section {
						Picker("Group", selection: $selectedGroupId) {
							Text("Personal").tag(Optional<UUID>.none)
							ForEach(groups.groups) { group in
								Text(group.name).tag(Optional(group.id))
							}
						}
						.pickerStyle(.menu)
					} header: {
						Text("Visible to")
					} footer: {
						Text(
							selectedGroupId == nil
								? "Only you will see this reminder."
								: "Everyone in the group can see this reminder on the map."
						)
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.dismissesKeyboardOnTap()
			.navigationTitle("New GeoReminder")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Add") { saveReminder() }
						.fontWeight(.semibold)
						.disabled(!canSave)
				}
			}
			.sheet(isPresented: $showingSearch) {
				SearchSheet(
					selectedCoordinate: $selectedCoordinate,
					selectedAddress: $selectedAddress
				)
			}
			.alert(
				"Add a title and choose a location",
				isPresented: $showingValidationAlert
			) {
				Button("OK", role: .cancel) {}
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
			.task {
				if auth.isAuthenticated {
					await groups.refresh()
				}
			}
		}
	}

	func saveReminder() {
		guard canSave, let coordinate = selectedCoordinate else {
			showingValidationAlert = true
			return
		}

		isSaving = true
		let flags = notifyMode.flags
		Task {
			do {
				try await reminders.add(
					title: title,
					desc: desc,
					latitude: coordinate.latitude,
					longitude: coordinate.longitude,
					radius: radius,
					notifyOnEntry: flags.entry,
					notifyOnExit: flags.exit,
					groupId: selectedGroupId
				)
				sendPinAddedNotification(title: title)
				dismiss()
			} catch {
				saveError = error.localizedDescription
			}
			isSaving = false
		}
	}

	private func savedPlaceButton(_ kind: SavedPlaceKind) -> some View {
		let saved = settings.place(for: kind)
		return Button {
			if let saved {
				apply(saved, fallbackName: kind.title)
			} else {
				Task { await captureAndSave(kind) }
			}
		} label: {
			Label(
				saved == nil ? "Set \(kind.title)" : kind.title,
				systemImage: kind.symbol
			)
		}
		.disabled(isLocating)
	}

	private func apply(_ place: SavedPlace, fallbackName: String) {
		selectedCoordinate = place.coordinate
		selectedAddress =
			place.address.isEmpty ? fallbackName : place.address
	}

	private func saveSelected(as kind: SavedPlaceKind) {
		guard let coord = selectedCoordinate else { return }
		let address =
			selectedAddress.isEmpty ? kind.title : selectedAddress
		settings.setPlace(
			SavedPlace(
				address: address,
				latitude: coord.latitude,
				longitude: coord.longitude
			),
			for: kind
		)
	}

	private func captureAndSave(_ kind: SavedPlaceKind) async {
		isLocating = true
		GeofenceManager.shared.requestWhenInUseAuthorization()
		defer { isLocating = false }
		guard let coord = await getCurrentLocation() else { return }
		let address = await reverseAddress(for: coord)
		let place = SavedPlace(
			address: address.isEmpty ? kind.title : address,
			latitude: coord.latitude,
			longitude: coord.longitude
		)
		settings.setPlace(place, for: kind)
		apply(place, fallbackName: kind.title)
	}
}

#Preview {
	Add()
		.environment(ReminderStore.shared)
		.environment(GroupStore.shared)
		.environment(AuthService.shared)
		.environment(AppSettings.shared)
}
