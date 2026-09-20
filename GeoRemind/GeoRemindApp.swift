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
		GeofenceNotify.register()
		GeofenceManager.shared.preload()
		NetworkMonitor.shared.start()
		AuthService.shared.start()
	}

	var body: some Scene {
		WindowGroup {
			RootView(hasCompletedOnboarding: $hasCompletedOnboarding)
				.environment(AuthService.shared)
				.environment(ReminderStore.shared)
				.environment(GroupStore.shared)
				.environment(AppSettings.shared)
				.environment(NetworkMonitor.shared)
				.onOpenURL { url in
					Task {
						if url.host == "join" {
							await GroupStore.shared.handleInviteURL(url)
						} else {
							await AuthService.shared.handleOpenURL(url)
						}
					}
				}
		}
	}
}

struct RootView: View {
	@Binding var hasCompletedOnboarding: Bool
	@Environment(AuthService.self) private var auth
	@Environment(AppSettings.self) private var settings

	var body: some View {
		Group {
			if !hasCompletedOnboarding {
				OnboardingView()
			} else if auth.isRestoringSession {
				ProgressView()
			} else {
				Home()
			}
		}
		.dismissesKeyboardOnTap()
		.preferredColorScheme(settings.appearance.colorScheme)
		.onChange(of: auth.isAuthenticated) { _, signedIn in
			if signedIn {
				Task { await GroupStore.shared.redeemPendingInvite() }
			}
		}
	}
}
