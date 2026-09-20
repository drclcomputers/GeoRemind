//
//  GeofenceManagerServ.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 16/09/2026.
//

import CoreLocation
import Observation
import UserNotifications

@Observable
final class GeofenceManager: NSObject, CLLocationManagerDelegate {
	static let shared = GeofenceManager()
	private let manager = CLLocationManager()

	var authorizationStatus: CLAuthorizationStatus
	var userCoordinate: CLLocationCoordinate2D?

	var totalActiveCount: Int = 0
	var isOverRegionLimit: Bool { totalActiveCount > regionLimit }

	private let regionLimit = 20
	private var lastLocation: CLLocationCoordinate2D?
	private var cachedPins: [ReminderPin] = []
	private var mute = GeofenceMute.load()

	private override init() {
		authorizationStatus = CLLocationManager().authorizationStatus
		super.init()
		manager.delegate = self
		cachedPins = PinCache.load()
	}

	func preload() {
		cachedPins = PinCache.load()
		syncRegions(pins: cachedPins)
	}

	func requestWhenInUseAuthorization() {
		manager.requestWhenInUseAuthorization()
	}

	private var hasRequestedAlways: Bool {
		get { UserDefaults.standard.bool(forKey: "hasRequestedAlwaysAuth") }
		set {
			UserDefaults.standard.set(
				newValue,
				forKey: "hasRequestedAlwaysAuth"
			)
		}
	}

	func requestAlwaysAuthorization() {
		if hasRequestedAlways {
			openAppSettings()
		} else {
			hasRequestedAlways = true
			manager.requestAlwaysAuthorization()
		}
	}

	func syncRegions(pins: [ReminderPin]? = nil) {
		if let pins {
			cachedPins = pins
		}

		for region in manager.monitoredRegions {
			manager.stopMonitoring(for: region)
		}

		let activePins = cachedPins.filter(\.isActive)
		totalActiveCount = activePins.count

		guard authorizationStatus == .authorizedAlways else { return }

		let candidates: [ReminderPin]
		if let here = lastLocation ?? userCoordinate {
			let userLoc = CLLocation(
				latitude: here.latitude,
				longitude: here.longitude
			)
			candidates =
				activePins
				.sorted { a, b in
					let da = CLLocation(
						latitude: a.coordinate.latitude,
						longitude: a.coordinate.longitude
					).distance(from: userLoc)
					let db = CLLocation(
						latitude: b.coordinate.latitude,
						longitude: b.coordinate.longitude
					).distance(from: userLoc)
					return da < db
				}
		} else {
			candidates = activePins
		}

		for pin in candidates.prefix(regionLimit)
		where pin.notifyOnEntry || pin.notifyOnExit {
			let radius = min(
				pin.radius,
				manager.maximumRegionMonitoringDistance
			)
			let region = CLCircularRegion(
				center: pin.coordinate,
				radius: radius,
				identifier: pin.id.uuidString
			)
			region.notifyOnEntry = pin.notifyOnEntry
			region.notifyOnExit = pin.notifyOnExit
			manager.startMonitoring(for: region)
		}
	}

	func startDistanceUpdates() {
		manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
		manager.requestLocation()
		switch authorizationStatus {
		case .authorizedAlways:
			manager.startMonitoringSignificantLocationChanges()
		case .authorizedWhenInUse:
			manager.startUpdatingLocation()
		default:
			break
		}
	}

	func stopDistanceUpdates() {
		if authorizationStatus != .authorizedAlways {
			manager.stopUpdatingLocation()
		}
	}

	func distance(to pin: ReminderPin) -> CLLocationDistance? {
		guard let here = userCoordinate ?? lastLocation else { return nil }
		return CLLocation(
			latitude: here.latitude,
			longitude: here.longitude
		).distance(
			from: CLLocation(
				latitude: pin.coordinate.latitude,
				longitude: pin.coordinate.longitude
			)
		)
	}

	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		authorizationStatus = manager.authorizationStatus
		if authorizationStatus == .authorizedAlways {
			manager.startMonitoringSignificantLocationChanges()
			syncRegions()
		} else {
			manager.stopMonitoringSignificantLocationChanges()
			syncRegions()
		}
	}

	func locationManager(
		_ manager: CLLocationManager,
		didUpdateLocations locations: [CLLocation]
	) {
		guard let coordinate = locations.last?.coordinate else { return }
		DispatchQueue.main.async { [weak self] in
			self?.userCoordinate = coordinate
			self?.lastLocation = coordinate
			self?.syncRegions()
		}
	}

	func locationManager(
		_ manager: CLLocationManager,
		didFailWithError error: Error
	) {
		print("Location update failed: \(error)")
	}

	func locationManager(
		_ manager: CLLocationManager,
		didEnterRegion region: CLRegion
	) {
		handle(region, event: .arrival)
	}

	func locationManager(
		_ manager: CLLocationManager,
		didExitRegion region: CLRegion
	) {
		handle(region, event: .departure)
	}

	func locationManager(
		_ manager: CLLocationManager,
		monitoringDidFailFor region: CLRegion?,
		withError error: Error
	) {
		print(
			"Geofence monitoring failed for \(region?.identifier ?? "unknown"): \(error)"
		)
	}

	private func activePin(for region: CLRegion) -> ReminderPin? {
		cachedPins.first {
			$0.id.uuidString == region.identifier && $0.isActive
		}
	}

	enum GeofenceEvent {
		case arrival
		case departure
	}

	private func handle(_ region: CLRegion, event: GeofenceEvent) {
		guard let pin = activePin(for: region) else { return }
		switch event {
		case .arrival:
			guard pin.notifyOnEntry else { return }
		case .departure:
			guard pin.notifyOnExit else { return }
		}
		guard pin.shouldFire() else { return }
		if mute.blocks(pin.id, event: event) { return }
		sendNotification(for: pin, event: event)
		mute.didFire(pin.id)
		if !pin.repeats {
			Task { await ReminderStore.shared.setActive(pin, isActive: false) }
		}
	}

	func handleNotificationAction(
		_ action: String,
		pinId: UUID,
		eventRaw: String
	) {
		let event: GeofenceEvent =
			eventRaw == "departure" ? .departure : .arrival
		switch action {
		case GeofenceNotify.skip:
			mute.skip(pinId, event: event)
		case GeofenceNotify.snooze:
			mute.snooze(pinId, for: 60 * 60)
		default:
			return
		}
	}

	private func sendNotification(for pin: ReminderPin, event: GeofenceEvent) {
		let content = UNMutableNotificationContent()

		switch event {
		case .arrival:
			content.title = pin.title
			content.body =
				pin.desc.isEmpty
				? loc(
					"Hey! You're in the proximity of this GeoReminder's location!"
				)
				: pin.desc
		case .departure:
			content.title = loc("Don't forget!")
			content.body = loc(
				"Hey! Don't forget about your GeoReminder at \"\(pin.title)\"!"
			)
		}

		content.sound = .default
		content.categoryIdentifier = pin.repeats ? GeofenceNotify.category : ""
		content.userInfo = [
			"pinId": pin.id.uuidString,
			"event": event == .arrival ? "arrival" : "departure",
		]

		let identifierPrefix = event == .arrival ? "arrival" : "departure"
		let request = UNNotificationRequest(
			identifier:
				"\(identifierPrefix)-\(pin.id.uuidString)-\(Date().timeIntervalSince1970)",
			content: content,
			trigger: nil
		)
		UNUserNotificationCenter.current().add(request)
	}
}

enum GeofenceNotify {
	static let category = "georemind.geofence"
	static let skip = "georemind.skip"
	static let snooze = "georemind.snooze"

	static func register() {
		let skip = UNNotificationAction(
			identifier: Self.skip,
			title: loc("Skip"),
			options: []
		)
		let snooze = UNNotificationAction(
			identifier: Self.snooze,
			title: loc("Snooze 1h"),
			options: []
		)
		let category = UNNotificationCategory(
			identifier: Self.category,
			actions: [skip, snooze],
			intentIdentifiers: [],
			options: []
		)
		UNUserNotificationCenter.current().setNotificationCategories([category])
	}
}

private struct GeofenceMute: Codable {
	var snoozeUntil: [String: Date] = [:]
	var skipUntilExit: [String] = []
	var skipUntilEnter: [String] = []
	var cooldownUntil: [String: Date] = [:]

	private static let key = "georemind.geofenceMute"

	static func load() -> GeofenceMute {
		guard let data = UserDefaults.standard.data(forKey: key),
			let value = try? JSONDecoder().decode(GeofenceMute.self, from: data)
		else {
			return GeofenceMute()
		}
		return value
	}

	func save() {
		guard let data = try? JSONEncoder().encode(self) else { return }
		UserDefaults.standard.set(data, forKey: Self.key)
	}

	mutating func didFire(_ pinId: UUID) {
		cooldownUntil[pinId.uuidString] = Date().addingTimeInterval(120)
		save()
	}

	mutating func skip(_ pinId: UUID, event: GeofenceManager.GeofenceEvent) {
		let key = pinId.uuidString
		switch event {
		case .arrival:
			if !skipUntilExit.contains(key) { skipUntilExit.append(key) }
		case .departure:
			if !skipUntilEnter.contains(key) { skipUntilEnter.append(key) }
		}
		save()
	}

	mutating func snooze(_ pinId: UUID, for seconds: TimeInterval) {
		snoozeUntil[pinId.uuidString] = Date().addingTimeInterval(seconds)
		save()
	}

	mutating func blocks(
		_ pinId: UUID,
		event: GeofenceManager.GeofenceEvent
	) -> Bool {
		let key = pinId.uuidString
		let now = Date()
		if let until = snoozeUntil[key] {
			if until > now { return true }
			snoozeUntil[key] = nil
		}
		if let until = cooldownUntil[key] {
			if until > now { return true }
			cooldownUntil[key] = nil
		}
		switch event {
		case .arrival:
			if skipUntilExit.contains(key) { return true }
			skipUntilEnter.removeAll { $0 == key }
		case .departure:
			if skipUntilEnter.contains(key) { return true }
			skipUntilExit.removeAll { $0 == key }
		}
		save()
		return false
	}
}
