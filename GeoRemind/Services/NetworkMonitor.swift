//
//  NetworkMonitor.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 20/09/2026.
//

import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
	static let shared = NetworkMonitor()

	var isOnline = true

	@ObservationIgnored
	private let monitor = NWPathMonitor()
	@ObservationIgnored
	private let queue = DispatchQueue(label: "georemind.network")
	@ObservationIgnored
	private var started = false

	private init() {}

	func start() {
		guard !started else { return }
		started = true
		monitor.pathUpdateHandler = { path in
			let online = path.status == .satisfied
			Task { @MainActor in
				NetworkMonitor.shared.isOnline = online
			}
		}
		monitor.start(queue: queue)
	}
}
