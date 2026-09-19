//
//  ReminderPin.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import CoreLocation
import Foundation
import SwiftUI

struct ReminderPin: Identifiable, Codable, Equatable, Hashable {
	var id: UUID
	var ownerId: UUID
	var groupId: UUID?
	var title: String
	var desc: String
	var latitude: Double
	var longitude: Double
	var radius: Double
	var isActive: Bool
	var timestamp: Date
	var notifyOnEntry: Bool
	var notifyOnExit: Bool

	enum CodingKeys: String, CodingKey {
		case id
		case ownerId
		case groupId
		case title
		case desc = "description"
		case latitude
		case longitude
		case radius
		case isActive
		case timestamp = "createdAt"
		case notifyOnEntry
		case notifyOnExit
	}

	init(
		id: UUID = UUID(),
		ownerId: UUID,
		groupId: UUID? = nil,
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
		self.id = id
		self.ownerId = ownerId
		self.groupId = groupId
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

	var isOwnedByCurrentUser: Bool {
		if let userId = AuthService.shared.userId {
			return ownerId == userId
		}
		return ownerId == LocalIdentity.ownerId
	}

	func isOwned(by userId: UUID?) -> Bool {
		guard let userId else { return false }
		return ownerId == userId
	}

	var notifyMode: NotifyMode {
		NotifyMode.from(entry: notifyOnEntry, exit: notifyOnExit)
	}
}

struct ReminderInsert: Encodable {
	var id: UUID
	var ownerId: UUID
	var groupId: UUID?
	var title: String
	var description: String
	var latitude: Double
	var longitude: Double
	var radius: Double
	var isActive: Bool
	var notifyOnEntry: Bool
	var notifyOnExit: Bool
}

struct ReminderUpdate: Encodable {
	var title: String
	var description: String
	var radius: Double
	var isActive: Bool
	var notifyOnEntry: Bool
	var notifyOnExit: Bool
	var groupId: UUID?
}

enum NotifyMode: String, CaseIterable, Identifiable {
	case arrival = "Arrival"
	case departure = "Departure"
	case both = "Both"

	var id: String { rawValue }

	var title: LocalizedStringKey {
		switch self {
		case .arrival: "Arrival"
		case .departure: "Departure"
		case .both: "Both"
		}
	}

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
