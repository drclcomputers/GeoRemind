//
//  NotificationServ.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 15/09/2026.
//

import Observation
import UIKit
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
	static let shared = NotificationDelegate()

	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler:
			@escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([.banner, .sound, .badge])
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let info = response.notification.request.content.userInfo
		if let raw = info["pinId"] as? String, let pinId = UUID(uuidString: raw)
		{
			let event = info["event"] as? String ?? "arrival"
			GeofenceManager.shared.handleNotificationAction(
				response.actionIdentifier,
				pinId: pinId,
				eventRaw: event
			)
		}
		completionHandler()
	}
}

@Observable
final class NotificationStatusMonitor {
	static let shared = NotificationStatusMonitor()

	var status: UNAuthorizationStatus = .notDetermined

	private init() {}

	func refresh() async {
		let settings = await UNUserNotificationCenter.current()
			.notificationSettings()
		status = settings.authorizationStatus
	}
}

func openAppSettings() {
	guard let url = URL(string: UIApplication.openSettingsURLString) else {
		return
	}
	UIApplication.shared.open(url)
}

func requestNotificationPermission() {
	UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

	UNUserNotificationCenter.current().requestAuthorization(options: [
		.alert, .sound, .badge,
	]) { granted, error in
		if let error {
			print("Notification permission error: \(error)")
		}
	}
}

func sendPinAddedNotification(title: String) {
	let content = UNMutableNotificationContent()
	content.title = "GeoRemind"
	content.body = "Hey! The GeoReminder \"\(title)\" has been added!"
	content.sound = .default

	let trigger = UNTimeIntervalNotificationTrigger(
		timeInterval: 1,
		repeats: false
	)
	let request = UNNotificationRequest(
		identifier: UUID().uuidString,
		content: content,
		trigger: trigger
	)

	UNUserNotificationCenter.current().add(request)
}
