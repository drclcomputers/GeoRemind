//
//  AppSettings.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 18/09/2026.
//

import Foundation
import Observation
import SwiftUI

enum MeasureUnits: String, CaseIterable, Identifiable {
	case metric
	case imperial

	var id: String { rawValue }

	var title: String {
		switch self {
		case .metric: "Metric"
		case .imperial: "Imperial"
		}
	}

	var caption: String {
		switch self {
		case .metric: "Meters, kilometers"
		case .imperial: "Feet, miles"
		}
	}
}

enum AppAppearance: String, CaseIterable, Identifiable {
	case system
	case light
	case dark

	var id: String { rawValue }

	var title: String {
		switch self {
		case .system: "System"
		case .light: "Light"
		case .dark: "Dark"
		}
	}

	var colorScheme: ColorScheme? {
		switch self {
		case .system: nil
		case .light: .light
		case .dark: .dark
		}
	}
}

@Observable
@MainActor
final class AppSettings {
	static let shared = AppSettings()

	var units: MeasureUnits {
		didSet { UserDefaults.standard.set(units.rawValue, forKey: keys.units) }
	}

	var appearance: AppAppearance {
		didSet {
			UserDefaults.standard.set(
				appearance.rawValue,
				forKey: keys.appearance
			)
		}
	}

	private enum keys {
		static let units = "settings.units"
		static let appearance = "settings.appearance"
	}

	private init() {
		units =
			MeasureUnits(
				rawValue: UserDefaults.standard.string(forKey: keys.units) ?? ""
			) ?? .metric
		appearance =
			AppAppearance(
				rawValue: UserDefaults.standard.string(forKey: keys.appearance)
					?? ""
			) ?? .system
	}

	func formatDistance(_ meters: Double) -> String {
		switch units {
		case .metric:
			if meters >= 1000 {
				return String(format: "%.1f km", meters / 1000)
			}
			return "\(Int(meters.rounded())) m"
		case .imperial:
			let feet = meters * 3.28084
			if feet >= 5280 {
				return String(format: "%.1f mi", feet / 5280)
			}
			return "\(Int(feet.rounded())) ft"
		}
	}
}
