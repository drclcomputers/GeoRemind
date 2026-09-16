//
//  GeofenceManagerServ.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 16/09/2026.
//

import CoreLocation
import Observation
import SwiftData
import UserNotifications

@Observable
final class GeofenceManager: NSObject, CLLocationManagerDelegate {
	static let shared = GeofenceManager()
	private let manager = CLLocationManager()
	private var context: ModelContext?

	var authorizationStatus: CLAuthorizationStatus

	var totalActiveCount: Int = 0
	var isOverRegionLimit: Bool { totalActiveCount > regionLimit }

	private let regionLimit = 20
	private let candidateRadius: CLLocationDistance = 2400
	private var lastLocation: CLLocationCoordinate2D?

	private override init() {
		authorizationStatus = CLLocationManager().authorizationStatus
		super.init()
		manager.delegate = self
	}

	func configure(context: ModelContext) {
		self.context = context
		syncRegions()
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
		let activePins: [ReminderPin]
		if let pins {
			activePins = pins.filter(\.isActive)
		} else if let context {
			let descriptor = FetchDescriptor<ReminderPin>(
				predicate: #Predicate { $0.isActive }
			)
			activePins = (try? context.fetch(descriptor)) ?? []
		} else {
			activePins = []
		}

		totalActiveCount = activePins.count

		guard authorizationStatus == .authorizedAlways else {
			for region in manager.monitoredRegions {
				manager.stopMonitoring(for: region)
			}
			return
		}

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

		let desiredPins = Dictionary(
			uniqueKeysWithValues: candidates.prefix(regionLimit).map {
				($0.id.uuidString, $0)
			}
		)
		let desiredIDs = Set(desiredPins.keys)
		let currentIDs = Set(manager.monitoredRegions.map(\.identifier))

		for region in manager.monitoredRegions
		where !desiredIDs.contains(region.identifier) {
			manager.stopMonitoring(for: region)
		}

		for id in desiredIDs.subtracting(currentIDs) {
			guard let pin = desiredPins[id] else { continue }
			let radius = min(
				pin.radius,
				manager.maximumRegionMonitoringDistance
			)
			let region = CLCircularRegion(
				center: pin.coordinate,
				radius: radius,
				identifier: id
			)
			region.notifyOnEntry = true
			region.notifyOnExit = false
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
		monitoringDidFailFor region: CLRegion?,
		withError error: Error
	) {
		print(
			"Geofence monitoring failed for \(region?.identifier ?? "unknown"): \(error)"
		)
	}

	private func sendArrivalNotification(for pin: ReminderPin) {
		let content = UNMutableNotificationContent()
		content.title = pin.title
		content.body =
			pin.desc.isEmpty
			? "You've arrived at this reminder's location." : pin.desc
		content.sound = .default

		let request = UNNotificationRequest(
			identifier:
				"arrival-\(pin.id.uuidString)-\(Date().timeIntervalSince1970)",
			content: content,
			trigger: nil
		)
		UNUserNotificationCenter.current().add(request)
	}
}
