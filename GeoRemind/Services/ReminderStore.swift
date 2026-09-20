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
		guard NetworkMonitor.shared.isOnline else { return }
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
			var merged = cloud
			let pending = PendingSync.load()
			if !pending.deleted.isEmpty {
				merged.removeAll { pending.deleted.contains($0.id) }
			}
			for upsert in pending.upserts {
				if let index = merged.firstIndex(where: { $0.id == upsert.id })
				{
					merged[index] = upsert
				} else {
					merged.insert(upsert, at: 0)
				}
			}
			pins = merged
			PinCache.save(merged)
			GeofenceManager.shared.syncRegions(pins: merged)
			errorMessage = nil
			await flushPending(pending)
		} catch {
			if !isIgnorableNetworkError(error) {
				errorMessage = error.localizedDescription
			}
		}
	}

	func handleSignedIn() async {
		await uploadLocalPinsToCloud()
		await flushPending(PendingSync.load())
		await refresh()
	}

	func handleSignedOut() {
		clear()
		PendingSync.clear()
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
			pin.asInsert(ownerId: userId)
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
		repeats: Bool = true,
		weekdays: Int = WeekdayMask.all,
		activeFromMinutes: Int? = nil,
		activeToMinutes: Int? = nil,
		existingId: UUID? = nil
	) async throws {
		let ownerId = AuthService.shared.userId ?? LocalIdentity.ownerId
		let pin = ReminderPin(
			id: existingId ?? UUID(),
			ownerId: ownerId,
			groupId: AuthService.shared.hasAccount ? groupId : nil,
			title: title,
			desc: desc,
			latitude: latitude,
			longitude: longitude,
			radius: radius,
			isActive: true,
			notifyOnEntry: notifyOnEntry,
			notifyOnExit: notifyOnExit,
			repeats: repeats,
			weekdays: weekdays,
			activeFromMinutes: activeFromMinutes,
			activeToMinutes: activeToMinutes
		)

		if let index = pins.firstIndex(where: { $0.id == pin.id }) {
			pins[index] = pin
		} else {
			pins.insert(pin, at: 0)
		}
		persistAndSync()

		guard AuthService.shared.isAuthenticated else {
			if AuthService.shared.hasAccount {
				PendingSync.queueUpsert(pin)
			}
			return
		}

		do {
			let write = pin.asInsert()
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
			}
			persistAndSync()
		} catch {
			PendingSync.queueUpsert(pin)
		}
	}

	func update(_ pin: ReminderPin) async throws {
		if let index = pins.firstIndex(where: { $0.id == pin.id }) {
			pins[index] = pin
			persistAndSync()
		}

		guard AuthService.shared.isAuthenticated,
			pin.ownerId == AuthService.shared.userId
		else {
			if AuthService.shared.hasAccount {
				PendingSync.queueUpsert(pin)
			}
			return
		}

		let write = ReminderUpdate(
			title: pin.title,
			description: pin.desc,
			radius: pin.radius,
			isActive: pin.isActive,
			notifyOnEntry: pin.notifyOnEntry,
			notifyOnExit: pin.notifyOnExit,
			groupId: pin.groupId,
			repeats: pin.repeats,
			weekdays: pin.weekdays,
			activeFromMinutes: pin.activeFromMinutes,
			activeToMinutes: pin.activeToMinutes
		)

		do {
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
		} catch {
			PendingSync.queueUpsert(pin)
		}
	}

	func setActive(_ pin: ReminderPin, isActive: Bool) async {
		var next = pin
		next.isActive = isActive
		if let index = pins.firstIndex(where: { $0.id == pin.id }) {
			pins[index].isActive = isActive
			persistAndSync()
		}
		guard AuthService.shared.isAuthenticated else {
			if AuthService.shared.hasAccount {
				PendingSync.queueUpsert(next)
			}
			return
		}
		try? await update(next)
	}

	func delete(_ pin: ReminderPin) async {
		pins.removeAll { $0.id == pin.id }
		persistAndSync()
		guard AuthService.shared.isAuthenticated else {
			if AuthService.shared.hasAccount {
				PendingSync.queueDelete(pin.id)
			}
			return
		}
		do {
			_ =
				try await supabase
				.from("reminders")
				.delete()
				.eq("id", value: pin.id)
				.execute()
		} catch {
			PendingSync.queueDelete(pin.id)
		}
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
		if !AuthService.shared.hasAccount {
			PinCache.savePendingGuest(
				pins.filter { $0.ownerId == LocalIdentity.ownerId }
			)
		}
		GeofenceManager.shared.syncRegions(pins: pins)
	}

	private func flushPending(_ pending: PendingSync) async {
		guard AuthService.shared.isAuthenticated, pending.hasWork else {
			return
		}
		for id in pending.deleted {
			do {
				_ = try await supabase.from("reminders").delete().eq(
					"id",
					value: id
				).execute()
			} catch {
				return
			}
		}
		for pin in pending.upserts where !pending.deleted.contains(pin.id) {
			let write = pin.asInsert()
			do {
				_ = try await supabase.from("reminders").upsert(write).execute()
			} catch {
				return
			}
		}
		PendingSync.clear()
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

struct PendingSync: Codable {
	var deleted: [UUID] = []
	var upserts: [ReminderPin] = []

	var hasWork: Bool { !deleted.isEmpty || !upserts.isEmpty }

	private static var fileURL: URL {
		let folder = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first!
		return folder.appendingPathComponent("georemind-pending-sync.json")
	}

	static func load() -> PendingSync {
		guard let data = try? Data(contentsOf: fileURL),
			let value = try? JSONCoders.decoder.decode(
				PendingSync.self,
				from: data
			)
		else {
			return PendingSync()
		}
		return value
	}

	func save() {
		guard let data = try? JSONCoders.encoder.encode(self) else { return }
		try? data.write(to: Self.fileURL, options: [.atomic])
	}

	static func clear() {
		try? FileManager.default.removeItem(at: fileURL)
	}

	static func queueUpsert(_ pin: ReminderPin) {
		var pending = load()
		pending.deleted.removeAll { $0 == pin.id }
		pending.upserts.removeAll { $0.id == pin.id }
		pending.upserts.append(pin)
		pending.save()
	}

	static func queueDelete(_ id: UUID) {
		var pending = load()
		pending.upserts.removeAll { $0.id == id }
		if !pending.deleted.contains(id) {
			pending.deleted.append(id)
		}
		pending.save()
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
