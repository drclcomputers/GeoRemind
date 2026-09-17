//
//  Add.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct Add: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss

	@State private var title = ""
	@State private var desc = ""
	@State private var radius: Double = 200
	@State private var notifyMode: NotifyMode = .arrival
	@State private var selectedCoordinate: CLLocationCoordinate2D?
	@State private var selectedAddress: String = ""
	@State private var showingSearch = false
	@State private var showingValidationAlert = false
	@State private var isLocating = false

	@FocusState private var focusedField: Field?

	private enum Field {
		case title, description
	}

	private var canSave: Bool {
		!title.trimmingCharacters(in: .whitespaces).isEmpty
			&& selectedCoordinate != nil
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
				}

				if selectedCoordinate != nil {
					Section("Radius") {
						VStack(alignment: .leading, spacing: 8) {
							Text("\(Int(radius)) m")
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
		}
	}

	func saveReminder() {
		guard canSave, let coordinate = selectedCoordinate else {
			showingValidationAlert = true
			return
		}

		let flags = notifyMode.flags
		let pin = ReminderPin(
			title: title,
			desc: desc,
			latitude: coordinate.latitude,
			longitude: coordinate.longitude,
			radius: radius,
			notifyOnEntry: flags.entry,
			notifyOnExit: flags.exit
		)
		context.insert(pin)

		sendPinAddedNotification(title: title)
		dismiss()
	}
}

#Preview {
	Add()
}
