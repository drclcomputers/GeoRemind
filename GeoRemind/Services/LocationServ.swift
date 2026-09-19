//
//  LocationServ.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import CoreLocation
import MapKit
import Observation

func getCurrentLocation() async -> CLLocationCoordinate2D? {
	do {
		let updates = CLLocationUpdate.liveUpdates()
		for try await update in updates {
			if let location = update.location {
				return location.coordinate
			}
		}
	} catch {
		print("error: \(error)")
	}
	return nil
}

func reverseAddress(for coordinate: CLLocationCoordinate2D) async -> String {
	let location = CLLocation(
		latitude: coordinate.latitude,
		longitude: coordinate.longitude
	)
	guard let request = MKReverseGeocodingRequest(location: location),
		let item = try? await request.mapItems.first
	else {
		return ""
	}
	if let short = item.address?.shortAddress, !short.isEmpty {
		return short
	}
	return item.name ?? ""
}

func resolveCoordinate(for completion: MKLocalSearchCompletion) async
	-> CLLocationCoordinate2D?
{
	let request = MKLocalSearch.Request(completion: completion)
	let search = MKLocalSearch(request: request)
	do {
		let response = try await search.start()
		return response.mapItems.first?.location.coordinate
	} catch {
		print("Resolve error: \(error)")
		return nil
	}
}
