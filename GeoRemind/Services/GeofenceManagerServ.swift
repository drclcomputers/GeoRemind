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

	var totalActiveCount: Int = 0
	var isOverRegionLimit: Bool { totalActiveCount > regionLimit }

	private let regionLimit = 20
	private let candidateRadius: CLLocationDistance = 2400
	private var lastLocation: CLLocationCoordinate2D?
	private var cachedPins: [ReminderPin] = []

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
		if let lastLocation {
			let userLoc = CLLocation(
				latitude: lastLocation.latitude,
				longitude: lastLocation.longitude
			)
			candidates =
				activePins
				.map { pin -> (ReminderPin, CLLocationDistance) in
					let pinLoc = CLLocation(
						latitude: pin.coordinate.latitude,
						longitude: pin.coordinate.longitude
					)
					return (pin, pinLoc.distance(from: userLoc))
				}
				.filter { $0.1 <= candidateRadius }
				.sorted { $0.1 < $1.1 }
				.map(\.0)
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
		lastLocation = coordinate
		syncRegions()
	}

	func locationManager(
		_ manager: CLLocationManager,
		didEnterRegion region: CLRegion
	) {
		guard let pin = activePin(for: region), pin.notifyOnEntry else {
			return
		}
		sendNotification(for: pin, event: .arrival)
	}

	func locationManager(
		_ manager: CLLocationManager,
		didExitRegion region: CLRegion
	) {
		guard let pin = activePin(for: region), pin.notifyOnExit else { return }
		sendNotification(for: pin, event: .departure)
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

	private enum GeofenceEvent {
		case arrival
		case departure
	}

	private func sendNotification(for pin: ReminderPin, event: GeofenceEvent) {
		let content = UNMutableNotificationContent()

		switch event {
		case .arrival:
			content.title = pin.title
			content.body =
				pin.desc.isEmpty
				? "Hey! You're in the proximity of this GeoReminder's location!"
				: pin.desc
		case .departure:
			content.title = "Don't forget!"
			content.body =
				"Hey! Don't forget about your GeoReminder at \"\(pin.title)\"!"
		}

		content.sound = .default

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
