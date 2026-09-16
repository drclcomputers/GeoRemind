//
//  ContentView.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import SwiftData
import SwiftUI

struct Home: View {
	@Environment(\.modelContext) private var context
	@Query private var pins: [ReminderPin]

	@State private var selectedTab = 0
	@State private var showingAdd = false

	var body: some View {
		TabView(selection: $selectedTab) {
			Tab("Map", systemImage: "map", value: 0) {
				NavigationStack {
					MapScreen(showingAdd: $showingAdd)
				}
			}
			Tab("Reminders", systemImage: "list.bullet", value: 1) {
				NavigationStack {
					Profile()
				}
			}
		}
		.sheet(isPresented: $showingAdd) {
			Add()
		}
		.task {
			GeofenceManager.shared.configure(context: context)
		}
		.onChange(of: pins) { _, newPins in
			GeofenceManager.shared.syncRegions(pins: newPins)
		}
	}
}

#Preview {
	Home()
}
