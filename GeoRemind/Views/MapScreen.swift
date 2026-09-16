//
//  MapScreen.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import MapKit
import SwiftData
import SwiftUI

struct MapScreen: View {
	@Binding var showingAdd: Bool

	@Environment(\.scenePhase) private var scenePhase

	@Query(sort: \ReminderPin.timestamp, order: .reverse) private var pins:
		[ReminderPin]
	@State private var position: MapCameraPosition = .automatic
	@State private var selectedPin: ReminderPin?

	var body: some View {
		ZStack(alignment: .bottomTrailing) {
			Map(position: $position) {
				UserAnnotation()
				ForEach(pins) { pin in
					Annotation(pin.title, coordinate: pin.coordinate) {
						Button {
							selectedPin = pin
						} label: {
							ZStack {
								Circle()
									.fill(
										pin.isActive
											? Color.accentColor : Color.gray
									)
									.frame(width: 32, height: 32)
									.shadow(
										color: .black.opacity(0.2),
										radius: 3,
										y: 2
									)
								Image(systemName: "mappin")
									.font(.system(size: 15, weight: .bold))
									.foregroundStyle(.white)
							}
						}
						.buttonStyle(.plain)
					}

					MapCircle(center: pin.coordinate, radius: pin.radius)
						.foregroundStyle(
							Color.accentColor.opacity(
								pin.isActive ? 0.12 : 0.05
							)
						)
						.stroke(
							pin.isActive ? Color.accentColor : Color.gray,
							lineWidth: 1
						)
				}
			}
			.mapControls {
				MapCompass()
				MapScaleView()
				MapUserLocationButton()
			}
			.mapStyle(.standard(pointsOfInterest: .excludingAll))

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
		.sheet(item: $selectedPin) { pin in
			PinDetailSheet(pin: pin)
		}
		.safeAreaInset(edge: .top) {
			permissionBanner
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				HStack(spacing: 6) {
					Text("GeoRemind")
						.font(.custom("ReemKufiFun-Regular_Bold", size: 26))
					Image(systemName: "mappin")
						.font(.system(size: 16))
						.rotationEffect(.degrees(10))
				}
			}
		}
		.task {
			await NotificationStatusMonitor.shared.refresh()
		}
		.onChange(of: scenePhase) { _, newPhase in
			if newPhase == .active {
				Task { await NotificationStatusMonitor.shared.refresh() }
			}
		}
	}

	@ViewBuilder
	private var permissionBanner: some View {
		let locationStatus = GeofenceManager.shared.authorizationStatus

		if locationStatus == .denied || locationStatus == .restricted {
			PermissionBanner(
				icon: "location.slash",
				message:
					"Location access is off. Reminders can't be shown or triggered.",
				actionTitle: "Open Settings",
				action: openAppSettings
			)
		} else if NotificationStatusMonitor.shared.status == .denied {
			PermissionBanner(
				icon: "bell.slash",
				message:
					"Notifications are off. You won't be alerted when you arrive.",
				actionTitle: "Open Settings",
				action: openAppSettings
			)
		} else if locationStatus == .authorizedWhenInUse {
			PermissionBanner(
				icon: "location.slash",
				message:
					"Allow \"Always\" location to get reminders in the background.",
				actionTitle: "Enable",
				action: { GeofenceManager.shared.requestAlwaysAuthorization() }
			)
		}
	}
}

struct PermissionBanner: View {
	let icon: String
	let message: String
	var actionTitle: String? = nil
	var action: (() -> Void)? = nil
	var tint: Color = .orange

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: icon)
				.foregroundStyle(tint)
			Text(message)
				.font(.footnote)
				.foregroundStyle(.secondary)
			Spacer()
			if let actionTitle, let action {
				Button(actionTitle, action: action)
					.font(.footnote.bold())
			}
		}
		.padding(10)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
		.padding(.horizontal)
		.padding(.top, 8)
	}
}

#Preview {
	NavigationStack {
		MapScreen(showingAdd: .constant(false))
	}
}
