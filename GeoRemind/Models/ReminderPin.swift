//
//  ReminderPin.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import CoreLocation
import Foundation
import SwiftData

@Model
class ReminderPin {
	var id: UUID = UUID()
	var title: String
	var desc: String
	var latitude: Double
	var longitude: Double
	var radius: Double
	var isActive: Bool
	var timestamp: Date
	var notifyOnEntry: Bool
	var notifyOnExit: Bool

	init(
		title: String,
		desc: String,
		latitude: Double,
		longitude: Double,
		radius: Double,
		isActive: Bool = true,
		timestamp: Date = .now,
		notifyOnEntry: Bool = true,
		notifyOnExit: Bool = false
	) {
		self.title = title
		self.desc = desc
		self.latitude = latitude
		self.longitude = longitude
		self.radius = radius
		self.isActive = isActive
		self.timestamp = timestamp
		self.notifyOnEntry = notifyOnEntry
		self.notifyOnExit = notifyOnExit
	}

	var coordinate: CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}
}

enum NotifyMode: String, CaseIterable, Identifiable {
	case arrival = "Arrival"
	case departure = "Departure"
	case both = "Both"

	var id: String { rawValue }

	var flags: (entry: Bool, exit: Bool) {
		switch self {
		case .arrival: return (true, false)
		case .departure: return (false, true)
		case .both: return (true, true)
		}
	}

	static func from(entry: Bool, exit: Bool) -> NotifyMode {
		switch (entry, exit) {
		case (true, false): return .arrival
		case (false, true): return .departure
		case (true, true): return .both
		default: return .arrival
		}
	}
}
