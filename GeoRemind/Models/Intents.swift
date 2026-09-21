//
//  Intents.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 21/09/2026.
//

import AppIntents
import CoreLocation
import Foundation

struct AddReminderHereIntent: AppIntent {
	static var title: LocalizedStringResource = "Add reminder here"
	static var description = IntentDescription(
		"Adds a GeoReminder at your current location."
	)
	static var openAppWhenRun = true

	@Parameter(title: "Title")
	var title: String

	static var parameterSummary: some ParameterSummary {
		Summary("Add \(\.$title) here")
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else {
			throw AddHereError.noTitle
		}

		GeofenceManager.shared.requestWhenInUseAuthorization()
		guard let coordinate = await resolveCoordinate() else {
			throw AddHereError.noLocation
		}

		try await ReminderStore.shared.add(
			title: name,
			desc: "",
			latitude: coordinate.latitude,
			longitude: coordinate.longitude,
			radius: 200,
			notifyOnEntry: true,
			notifyOnExit: false,
			groupId: nil
		)
		sendPinAddedNotification(title: name)
		return .result(
			dialog: IntentDialog(
				LocalizedStringResource(
					"Added \"\(name)\" at your current location."
				)
			)
		)
	}

	@MainActor
	private func resolveCoordinate() async -> CLLocationCoordinate2D? {
		if let here = GeofenceManager.shared.userCoordinate {
			return here
		}
		return await getCurrentLocation()
	}
}

enum AddHereError: Error, CustomLocalizedStringResourceConvertible {
	case noTitle
	case noLocation

	var localizedStringResource: LocalizedStringResource {
		switch self {
		case .noTitle:
			"Add a title."
		case .noLocation:
			"Couldn't get your location."
		}
	}
}

struct GeoRemindShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: AddReminderHereIntent(),
			phrases: [
				"Add a reminder here in \(.applicationName)",
				"Add a GeoReminder here in \(.applicationName)",
			],
			shortTitle: "Add here",
			systemImageName: "mappin.and.ellipse"
		)
	}
}
