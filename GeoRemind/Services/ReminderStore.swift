//
//  ReminderStore.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class ReminderStore {
	static let shared = ReminderStore()

	var pins: [ReminderPin] = []
	var isLoading = false
	var errorMessage: String?

	@ObservationIgnored
	private var realtimeTask: Task<Void, Never>?

	private init() {
		pins = PinCache.load()
	}

	func refresh() async {
		isLoading = true
		defer { isLoading = false }
		do {
			let fetched: [ReminderPin] =
				try await supabase
				.from("reminders")
				.select()
				.order("created_at", ascending: false)
				.execute()
				.value
			pins = fetched
			PinCache.save(fetched)
			GeofenceManager.shared.syncRegions(pins: fetched)
			errorMessage = nil
		} catch {
			errorMessage = error.localizedDescription
			if pins.isEmpty {
				pins = PinCache.load()
				GeofenceManager.shared.syncRegions(pins: pins)
			}
		}
	}

	func add(
		title: String,
		desc: String,
		latitude: Double,
		longitude: Double,
		radius: Double,
		notifyOnEntry: Bool,
		notifyOnExit: Bool,
		groupId: UUID?
	) async throws {
		guard let ownerId = AuthService.shared.userId else {
			throw StoreError.notSignedIn
		}

		let write = ReminderInsert(
			id: UUID(),
			ownerId: ownerId,
			groupId: groupId,
			title: title,
			description: desc,
			latitude: latitude,
			longitude: longitude,
			radius: radius,
			isActive: true,
			notifyOnEntry: notifyOnEntry,
			notifyOnExit: notifyOnExit
		)

		let inserted: ReminderPin =
			try await supabase
			.from("reminders")
			.insert(write)
			.select()
			.single()
			.execute()
			.value

		pins.insert(inserted, at: 0)
		persistAndSync()
	}

	func update(_ pin: ReminderPin) async throws {
		let write = ReminderUpdate(
			title: pin.title,
			description: pin.desc,
			radius: pin.radius,
			isActive: pin.isActive,
			notifyOnEntry: pin.notifyOnEntry,
			notifyOnExit: pin.notifyOnExit,
			groupId: pin.groupId
		)

		let updated: ReminderPin =
			try await supabase
			.from("reminders")
			.update(write)
			.eq("id", value: pin.id)
			.select()
			.single()
			.execute()
			.value

		if let index = pins.firstIndex(where: { $0.id == pin.id }) {
			pins[index] = updated
		}
		persistAndSync()
	}

	func setActive(_ pin: ReminderPin, isActive: Bool) async {
		var next = pin
		next.isActive = isActive
		if let index = pins.firstIndex(where: { $0.id == pin.id }) {
			pins[index].isActive = isActive
			persistAndSync()
		}
		try? await update(next)
	}

	func delete(_ pin: ReminderPin) async {
		pins.removeAll { $0.id == pin.id }
		persistAndSync()
		try? await supabase
			.from("reminders")
			.delete()
			.eq("id", value: pin.id)
			.execute()
	}

	func pin(id: UUID) -> ReminderPin? {
		pins.first { $0.id == id }
	}

	func clear() {
		realtimeTask?.cancel()
		realtimeTask = nil
		pins = []
		PinCache.save([])
		GeofenceManager.shared.syncRegions(pins: [])
	}

	func startRealtime() {
		realtimeTask?.cancel()
		realtimeTask = Task {
			let channel = supabase.channel("reminders-sync")
			let stream = channel.postgresChange(
				AnyAction.self,
				schema: "public",
				table: "reminders"
			)
			await channel.subscribe()
			for await _ in stream {
				guard !Task.isCancelled else { break }
				await refresh()
			}
		}
	}

	private func persistAndSync() {
		PinCache.save(pins)
		GeofenceManager.shared.syncRegions(pins: pins)
	}
}

enum StoreError: LocalizedError {
	case notSignedIn

	var errorDescription: String? {
		switch self {
		case .notSignedIn: return "You need to be signed in."
		}
	}
}

enum PinCache {
	private static var fileURL: URL {
		let folder = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first!
		try? FileManager.default.createDirectory(
			at: folder,
			withIntermediateDirectories: true
		)
		return folder.appendingPathComponent("georemind-pins.json")
	}

	static func load() -> [ReminderPin] {
		guard let data = try? Data(contentsOf: fileURL) else { return [] }
		return (try? JSONCoders.decoder.decode([ReminderPin].self, from: data))
			?? []
	}

	static func save(_ pins: [ReminderPin]) {
		guard let data = try? JSONCoders.encoder.encode(pins) else { return }
		try? data.write(to: fileURL, options: [.atomic])
	}
}
