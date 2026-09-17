//
//  GeoRemindApp.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import SwiftUI
import UserNotifications

@main
struct GeoRemindApp: App {
	@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding =
		false

	init() {
		UNUserNotificationCenter.current().delegate =
			NotificationDelegate.shared
		GeofenceManager.shared.preload()
		AuthService.shared.start()
	}

	var body: some Scene {
		WindowGroup {
			RootView(hasCompletedOnboarding: $hasCompletedOnboarding)
				.environment(AuthService.shared)
				.environment(ReminderStore.shared)
				.environment(GroupStore.shared)
				.onOpenURL { url in
					Task { await AuthService.shared.handleOpenURL(url) }
				}
		}
	}
}

struct RootView: View {
	@Binding var hasCompletedOnboarding: Bool
	@Environment(AuthService.self) private var auth

	var body: some View {
		Group {
			if !hasCompletedOnboarding {
				OnboardingView()
			} else if auth.isRestoringSession {
				ProgressView()
			} else if auth.isAuthenticated {
				Home()
			} else {
				AuthView()
			}
		}
		.dismissesKeyboardOnTap()
	}
}
