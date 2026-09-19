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
	@ObservationIgnored
	private var pendingGuestPins: [ReminderPin] = []

	private init() {
		pins = PinCache.load()
	}

	func refresh() async {
		await pullFromCloud(showLoading: true)
		startRealtime()
	}

	private func pullFromCloud(showLoading: Bool) async {
		guard AuthService.shared.isAuthenticated else {
			pins = PinCache.load()
			GeofenceManager.shared.syncRegions(pins: pins)
			return
		}

		if showLoading { isLoading = true }
		defer { if showLoading { isLoading = false } }
		do {
			let cloud: [ReminderPin] =
				try await supabase
				.from("reminders")
				.select()
				.order("created_at", ascending: false)
				.execute()
				.value
			pins = cloud
			PinCache.save(cloud)
			GeofenceManager.shared.syncRegions(pins: cloud)
			errorMessage = nil
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func handleSignedIn() async {
		await uploadLocalPinsToCloud()
		await refresh()
	}

	func handleSignedOut() {
		clear()
	}

	func snapshotGuestPins() {
		var guest = pins
		if guest.isEmpty {
			guest = PinCache.loadPendingGuest()
		}
		if guest.isEmpty {
			guest = PinCache.load()
		}
		pendingGuestPins = guest
		if !guest.isEmpty {
			PinCache.savePendingGuest(guest)
		}
	}

	var hasPendingGuestPins: Bool {
		!pendingGuestPins.isEmpty || !PinCache.loadPendingGuest().isEmpty
	}

	private func uploadLocalPinsToCloud() async {
		guard let userId = AuthService.shared.userId else { return }
		var guest = pendingGuestPins
		if guest.isEmpty {
			guest = PinCache.loadPendingGuest()
		}
		guard !guest.isEmpty else { return }

		let writes = guest.map { pin in
			ReminderInsert(
				id: pin.id,
				ownerId: userId,
				groupId: nil,
				title: pin.title,
				description: pin.desc,
				latitude: pin.latitude,
				longitude: pin.longitude,
				radius: pin.radius,
				isActive: pin.isActive,
				notifyOnEntry: pin.notifyOnEntry,
				notifyOnExit: pin.notifyOnExit
			)
		}

		do {
			try await supabase.from("reminders").upsert(writes).execute()
			pendingGuestPins = []
			PinCache.clearPendingGuest()
		} catch {
			do {
				for write in writes {
					try await supabase.from("reminders").upsert(write).execute()
				}
				pendingGuestPins = []
				PinCache.clearPendingGuest()
			} catch {
				errorMessage = error.localizedDescription
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
		groupId: UUID?,
		existingId: UUID? = nil
	) async throws {
		let ownerId = AuthService.shared.userId ?? LocalIdentity.ownerId
		let pin = ReminderPin(
			id: existingId ?? UUID(),
			ownerId: ownerId,
			groupId: AuthService.shared.isAuthenticated ? groupId : nil,
			title: title,
			desc: desc,
			latitude: latitude,
			longitude: longitude,
			radius: radius,
			isActive: true,
			notifyOnEntry: notifyOnEntry,
			notifyOnExit: notifyOnExit
		)

		if AuthService.shared.isAuthenticated {
			let write = ReminderInsert(
				id: pin.id,
				ownerId: ownerId,
				groupId: pin.groupId,
				title: pin.title,
				description: pin.desc,
				latitude: pin.latitude,
				longitude: pin.longitude,
				radius: pin.radius,
				isActive: true,
				notifyOnEntry: pin.notifyOnEntry,
				notifyOnExit: pin.notifyOnExit
			)
			let inserted: ReminderPin =
				try await supabase
				.from("reminders")
				.insert(write)
				.select()
				.single()
				.execute()
				.value
			if let index = pins.firstIndex(where: { $0.id == inserted.id }) {
				pins[index] = inserted
			} else {
				pins.insert(inserted, at: 0)
			}
		} else {
			pins.insert(pin, at: 0)
		}
		persistAndSync()
	}

	func update(_ pin: ReminderPin) async throws {
		if let index = pins.firstIndex(where: { $0.id == pin.id }) {
			pins[index] = pin
			persistAndSync()
		}

		guard AuthService.shared.isAuthenticated,
			pin.ownerId == AuthService.shared.userId
		else { return }

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
		guard AuthService.shared.isAuthenticated else { return }
		try? await update(next)
	}

	func delete(_ pin: ReminderPin) async {
		pins.removeAll { $0.id == pin.id }
		persistAndSync()
		guard AuthService.shared.isAuthenticated else { return }
		_ = try? await supabase
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
		guard AuthService.shared.isAuthenticated else { return }
		guard realtimeTask == nil else { return }
		realtimeTask = Task {
			let channel = supabase.channel("reminders-sync")
			let stream = channel.postgresChange(
				AnyAction.self,
				schema: "public",
				table: "reminders"
			)
			_ = try? await channel.subscribeWithError()
			for await _ in stream {
				guard !Task.isCancelled else { break }
				await pullFromCloud(showLoading: false)
			}
			await channel.unsubscribe()
			realtimeTask = nil
		}
	}

	private func persistAndSync() {
		PinCache.save(pins)
		if AuthService.shared.session == nil {
			PinCache.savePendingGuest(
				pins.filter { $0.ownerId == LocalIdentity.ownerId }
			)
		}
		GeofenceManager.shared.syncRegions(pins: pins)
	}
}

enum StoreError: LocalizedError {
	case notSignedIn

	var errorDescription: String? {
		switch self {
		case .notSignedIn: return loc("You need to be signed in.")
		}
	}
}

enum PinCache {
	private static var folder: URL {
		let folder = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first!
		try? FileManager.default.createDirectory(
			at: folder,
			withIntermediateDirectories: true
		)
		return folder
	}

	private static var fileURL: URL {
		folder.appendingPathComponent("georemind-pins.json")
	}

	private static var pendingGuestURL: URL {
		folder.appendingPathComponent("georemind-guest-pins.json")
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

	static func loadPendingGuest() -> [ReminderPin] {
		guard let data = try? Data(contentsOf: pendingGuestURL) else {
			return []
		}
		return (try? JSONCoders.decoder.decode([ReminderPin].self, from: data))
			?? []
	}

	static func savePendingGuest(_ pins: [ReminderPin]) {
		guard let data = try? JSONCoders.encoder.encode(pins) else { return }
		try? data.write(to: pendingGuestURL, options: [.atomic])
	}

	static func clearPendingGuest() {
		try? FileManager.default.removeItem(at: pendingGuestURL)
	}
}

enum LocalIdentity {
	static let ownerId: UUID = {
		let key = "georemind.localOwnerId"
		if let raw = UserDefaults.standard.string(forKey: key),
			let id = UUID(uuidString: raw)
		{
			return id
		}
		let id = UUID()
		UserDefaults.standard.set(id.uuidString, forKey: key)
		return id
	}()
}
