//
//  GeoRemindApp.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import SwiftData
import SwiftUI

@main
struct GeoRemindApp: App {
	private let notificationDelegate = NotificationDelegate()
	@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding =
		false

	init() {
		UNUserNotificationCenter.current().delegate = notificationDelegate
	}

	var body: some Scene {
		WindowGroup {
			if hasCompletedOnboarding {
				Home()
			} else {
				OnboardingView()
			}
		}
		.modelContainer(for: ReminderPin.self)
	}
}
