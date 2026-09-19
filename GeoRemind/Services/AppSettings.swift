//
//  AppSettings.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 18/09/2026.
//

import CoreLocation
import Foundation
import Observation
import SwiftUI

enum MeasureUnits: String, CaseIterable, Identifiable {
	case metric
	case imperial

	var id: String { rawValue }

	var title: LocalizedStringKey {
		switch self {
		case .metric: "Metric"
		case .imperial: "Imperial"
		}
	}

	var caption: LocalizedStringKey {
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

	var title: LocalizedStringKey {
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

enum AppLanguage: String, CaseIterable, Identifiable {
	case system
	case en
	case ro
	case fr
	case de
	case es
	case it
	case pt
	case pl
	case nl
	case uk
	case hu
	case tr
	case ja
	case zhHans = "zh-Hans"

	var id: String { rawValue }

	var nativeName: String {
		switch self {
		case .system: loc("System")
		case .en: "English"
		case .ro: "Română"
		case .fr: "Français"
		case .de: "Deutsch"
		case .es: "Español"
		case .it: "Italiano"
		case .pt: "Português"
		case .pl: "Polski"
		case .nl: "Nederlands"
		case .uk: "Українська"
		case .hu: "Magyar"
		case .tr: "Türkçe"
		case .ja: "日本語"
		case .zhHans: "简体中文"
		}
	}

	var locale: Locale {
		switch self {
		case .system: Locale.autoupdatingCurrent
		default: Locale(identifier: rawValue)
		}
	}
}

struct SavedPlace: Codable, Equatable, Hashable {
	var address: String
	var latitude: Double
	var longitude: Double

	var coordinate: CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}
}

enum SavedPlaceKind: String, CaseIterable, Identifiable {
	case home
	case work

	var id: String { rawValue }

	var title: LocalizedStringKey {
		switch self {
		case .home: "Home"
		case .work: "Work"
		}
	}

	var titleString: String {
		switch self {
		case .home: loc("Home")
		case .work: loc("Work")
		}
	}

	var symbol: String {
		switch self {
		case .home: "house.fill"
		case .work: "briefcase.fill"
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

	var home: SavedPlace? {
		didSet { savePlace(home, key: keys.home) }
	}

	var work: SavedPlace? {
		didSet { savePlace(work, key: keys.work) }
	}

	var language: AppLanguage {
		didSet {
			UserDefaults.standard.set(language.rawValue, forKey: keys.language)
		}
	}

	var resolvedLocale: Locale { language.locale }

	private enum keys {
		static let units = "settings.units"
		static let appearance = "settings.appearance"
		static let language = "settings.language"
		static let home = "settings.home"
		static let work = "settings.work"
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
		home = Self.loadPlace(keys.home)
		work = Self.loadPlace(keys.work)
		language =
			AppLanguage(
				rawValue: UserDefaults.standard.string(forKey: keys.language)
					?? ""
			) ?? .system
	}

	func place(for kind: SavedPlaceKind) -> SavedPlace? {
		switch kind {
		case .home: home
		case .work: work
		}
	}

	func setPlace(_ place: SavedPlace?, for kind: SavedPlaceKind) {
		switch kind {
		case .home: home = place
		case .work: work = place
		}
	}

	private func savePlace(_ place: SavedPlace?, key: String) {
		if let place, let data = try? JSONEncoder().encode(place) {
			UserDefaults.standard.set(data, forKey: key)
		} else {
			UserDefaults.standard.removeObject(forKey: key)
		}
	}

	private static func loadPlace(_ key: String) -> SavedPlace? {
		guard let data = UserDefaults.standard.data(forKey: key) else {
			return nil
		}
		return try? JSONDecoder().decode(SavedPlace.self, from: data)
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

func loc(_ value: String.LocalizationValue) -> String {
	String(
		localized: LocalizedStringResource(
			value,
			locale: AppSettings.shared.resolvedLocale
		)
	)
}
