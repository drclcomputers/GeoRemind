//
//  SearchSheet.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 15/09/2026.
//

import MapKit
import SwiftUI

struct SearchSheet: View {
	@Binding var selectedCoordinate: CLLocationCoordinate2D?
	@Binding var selectedAddress: String
	@Environment(\.dismiss) private var dismiss

	@State private var searchService = SearchService()
	@State private var searchText = ""

	var body: some View {
		NavigationStack {
			List(searchService.results, id: \.self) { result in
				Button {
					Task {
						selectedCoordinate = await resolveCoordinate(
							for: result
						)
						selectedAddress = result.title
						dismiss()
					}
				} label: {
					VStack(alignment: .leading, spacing: 2) {
						Text(result.title)
							.foregroundStyle(.primary)
						if !result.subtitle.isEmpty {
							Text(result.subtitle)
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
				}
			}
			.listStyle(.plain)
			.searchable(text: $searchText, prompt: "Search for an adress")
			.onChange(of: searchText) { _, newValue in
				searchService.updateQuery(newValue)
			}
			.navigationTitle("Search")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
			.task {
				if let existing = selectedCoordinate {
					searchService.updateRegion(existing)
				} else if let current = await getCurrentLocation() {
					searchService.updateRegion(current)
				}
			}
		}
	}
}

#Preview {
	SearchSheet(selectedCoordinate: .constant(nil), selectedAddress: .constant(""))
}
