//
//  Onboarding.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 16/09/2026.
//

import SwiftUI
import UserNotifications

struct OnboardingView: View {
	@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding =
		false
	@State private var page = 0
	@State private var isRequesting = false

	var body: some View {
		TabView(selection: $page) {
			introPage.tag(0)
			permissionsPage.tag(1)
		}
		.tabViewStyle(.page(indexDisplayMode: .always))
		.indexViewStyle(.page(backgroundDisplayMode: .always))
		.background(Color(.systemBackground))
		.interactiveDismissDisabled()
	}

	private var introPage: some View {
		VStack(spacing: 20) {
			Spacer()

			HStack(spacing: 8) {
				Text("GeoRemind")
					.font(.custom("ReemKufiFun-Regular_Bold", size: 34))
				Image(systemName: "mappin")
					.font(.system(size: 28))
					.rotationEffect(.degrees(10))
			}

			Image(systemName: "mappin.and.ellipse.circle.fill")
				.font(.system(size: 80))
				.foregroundStyle(Color.accentColor)
				.padding(.top, 8)

			Text("Never forget again")
				.font(.title2.bold())

			Text(
				"Set a reminder for a place, and GeoRemind will notify you the moment you get there."
			)
			.font(.body)
			.foregroundStyle(.secondary)
			.multilineTextAlignment(.center)
			.padding(.horizontal, 32)

			Spacer()

			Button {
				withAnimation { page = 1 }
			} label: {
				Text("Continue")
					.fontWeight(.semibold)
					.frame(maxWidth: .infinity)
					.padding()
					.background(Color.accentColor, in: Capsule())
					.foregroundStyle(.white)
			}
			.padding(.horizontal, 32)
			.padding(.bottom, 40)
		}
	}

	private var permissionsPage: some View {
		VStack(spacing: 20) {
			Spacer()

			Image(systemName: "location.circle.fill")
				.font(.system(size: 80))
				.foregroundStyle(Color.accentColor)

			Text("Two quick permissions")
				.font(.title2.bold())

			VStack(alignment: .leading, spacing: 18) {
				permissionRow(
					icon: "location.fill",
					title: "Location",
					detail:
						"So GeoRemind can tell when you're near a saved place. You can allow background access from the Map screen once you've added your first reminder."
				)
				permissionRow(
					icon: "bell.fill",
					title: "Notifications",
					detail: "So you actually get alerted when you arrive."
				)
			}
			.padding(.horizontal, 32)

			Spacer()

			Button {
				guard !isRequesting else { return }
				isRequesting = true
				Task {
					await requestPermissions()
					hasCompletedOnboarding = true
				}
			} label: {
				Text(isRequesting ? "Requesting…" : "Get Started")
					.fontWeight(.semibold)
					.frame(maxWidth: .infinity)
					.padding()
					.background(Color.accentColor, in: Capsule())
					.foregroundStyle(.white)
			}
			.disabled(isRequesting)
			.padding(.horizontal, 32)
			.padding(.bottom, 40)
		}
	}

	private func permissionRow(icon: String, title: String, detail: String)
		-> some View
	{
		HStack(alignment: .top, spacing: 14) {
			Image(systemName: icon)
				.font(.system(size: 20))
				.foregroundStyle(Color.accentColor)
				.frame(width: 28)
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(.subheadline.bold())
				Text(detail)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func requestPermissions() async {
		UNUserNotificationCenter.current().delegate =
			NotificationDelegate.shared
		_ = try? await UNUserNotificationCenter.current().requestAuthorization(
			options: [.alert, .sound, .badge]
		)
		await NotificationStatusMonitor.shared.refresh()

		GeofenceManager.shared.requestWhenInUseAuthorization()
	}
}

#Preview {
	OnboardingView()
}
