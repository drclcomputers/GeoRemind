//
//  ContentView.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import SwiftUI

struct Home: View {
	@Environment(ReminderStore.self) private var reminders

	@State private var selectedTab = 0
	@State private var showingAdd = false

	var body: some View {
		TabView(selection: $selectedTab) {
			Tab("Map", systemImage: "map", value: 0) {
				NavigationStack {
					MapScreen(showingAdd: $showingAdd)
				}
			}
			Tab("GeoReminders", systemImage: "list.bullet", value: 1) {
				NavigationStack {
					RemindersScreen()
				}
			}
			Tab("Profile", systemImage: "person", value: 2) {
				NavigationStack {
					Profile()
				}
			}
		}
		.sheet(isPresented: $showingAdd) {
			Add()
		}
		.task {
			GeofenceManager.shared.syncRegions(pins: reminders.pins)
			await NotificationStatusMonitor.shared.refresh()
		}
		.onChange(of: reminders.pins) { _, newPins in
			GeofenceManager.shared.syncRegions(pins: newPins)
		}
	}
}

#Preview {
	Home()
		.environment(AuthService.shared)
		.environment(ReminderStore.shared)
		.environment(GroupStore.shared)
}
