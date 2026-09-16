//
//  SearchServ.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 16/09/2026.
//

import MapKit
import Observation

@Observable
class SearchService: NSObject, MKLocalSearchCompleterDelegate {
	private let completer = MKLocalSearchCompleter()
	var results: [MKLocalSearchCompletion] = []

	override init() {
		super.init()
		completer.delegate = self
		completer.resultTypes = [.address, .pointOfInterest]
	}

	func updateRegion(_ coordinate: CLLocationCoordinate2D) {
		completer.region = MKCoordinateRegion(
			center: coordinate,
			latitudinalMeters: 50000,
			longitudinalMeters: 50000
		)
	}

	func updateQuery(_ query: String) {
		completer.queryFragment = query
	}

	func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
		results = completer.results
	}

	func completer(
		_ completer: MKLocalSearchCompleter,
		didFailWithError error: Error
	) {
		print("error: \(error)")
	}
}
