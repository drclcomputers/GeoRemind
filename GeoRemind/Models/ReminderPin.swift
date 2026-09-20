//
//  ReminderPin.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import CoreLocation
import Foundation
import SwiftUI

nonisolated struct ReminderPin: Identifiable, Codable, Equatable, Hashable,
	Sendable
{
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
	var repeats: Bool
	var weekdays: Int
	var activeFromMinutes: Int?
	var activeToMinutes: Int?

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
		case repeats
		case weekdays
		case activeFromMinutes
		case activeToMinutes
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
		notifyOnExit: Bool = false,
		repeats: Bool = true,
		weekdays: Int = WeekdayMask.all,
		activeFromMinutes: Int? = nil,
		activeToMinutes: Int? = nil
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
		self.repeats = repeats
		self.weekdays = weekdays
		self.activeFromMinutes = activeFromMinutes
		self.activeToMinutes = activeToMinutes
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decode(UUID.self, forKey: .id)
		ownerId = try c.decode(UUID.self, forKey: .ownerId)
		groupId = try c.decodeIfPresent(UUID.self, forKey: .groupId)
		title = try c.decode(String.self, forKey: .title)
		desc = try c.decodeIfPresent(String.self, forKey: .desc) ?? ""
		latitude = try c.decode(Double.self, forKey: .latitude)
		longitude = try c.decode(Double.self, forKey: .longitude)
		radius = try c.decode(Double.self, forKey: .radius)
		isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
		timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? .now
		notifyOnEntry =
			try c.decodeIfPresent(Bool.self, forKey: .notifyOnEntry) ?? true
		notifyOnExit =
			try c.decodeIfPresent(Bool.self, forKey: .notifyOnExit) ?? false
		repeats = try c.decodeIfPresent(Bool.self, forKey: .repeats) ?? true
		weekdays =
			try c.decodeIfPresent(Int.self, forKey: .weekdays) ?? WeekdayMask.all
		activeFromMinutes = try c.decodeIfPresent(
			Int.self,
			forKey: .activeFromMinutes
		)
		activeToMinutes = try c.decodeIfPresent(
			Int.self,
			forKey: .activeToMinutes
		)
	}

	var coordinate: CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}

	@MainActor
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

	func shouldFire(at date: Date = .now) -> Bool {
		guard isActive else { return false }
		guard WeekdayMask.contains(weekdays, date: date) else { return false }
		return DayMinutes.matches(
			from: activeFromMinutes,
			to: activeToMinutes,
			date: date
		)
	}

	var scheduleSummary: String {
		var parts = [repeats ? loc("Every time") : loc("Once")]
		parts.append(WeekdayMask.summary(weekdays))
		if let from = activeFromMinutes, let to = activeToMinutes {
			parts.append("\(DayMinutes.label(from))–\(DayMinutes.label(to))")
		}
		return parts.joined(separator: " · ")
	}

	func asInsert(ownerId: UUID? = nil) -> ReminderInsert {
		ReminderInsert(
			id: id,
			ownerId: ownerId ?? self.ownerId,
			groupId: groupId,
			title: title,
			description: desc,
			latitude: latitude,
			longitude: longitude,
			radius: radius,
			isActive: isActive,
			notifyOnEntry: notifyOnEntry,
			notifyOnExit: notifyOnExit,
			repeats: repeats,
			weekdays: weekdays,
			activeFromMinutes: activeFromMinutes,
			activeToMinutes: activeToMinutes
		)
	}
}

nonisolated struct ReminderInsert: Encodable, Sendable {
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
	var repeats: Bool
	var weekdays: Int
	var activeFromMinutes: Int?
	var activeToMinutes: Int?
}

nonisolated struct ReminderUpdate: Encodable, Sendable {
	var title: String
	var description: String
	var radius: Double
	var isActive: Bool
	var notifyOnEntry: Bool
	var notifyOnExit: Bool
	var groupId: UUID?
	var repeats: Bool
	var weekdays: Int
	var activeFromMinutes: Int?
	var activeToMinutes: Int?
}

nonisolated enum NotifyMode: String, CaseIterable, Identifiable, Sendable {
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
