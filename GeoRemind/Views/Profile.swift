//
//  Profile.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import SwiftUI

struct Profile: View {
	@Environment(AuthService.self) private var auth
	@Environment(GroupStore.self) private var groups

	@State private var editedUsername = ""
	@State private var isEditingUsername = false
	@State private var showingCreateGroup = false
	@State private var newGroupName = ""
	@State private var selectedGroup: GeoGroup?
	@State private var showingSignOut = false
	@State private var showingAuth = false

	var body: some View {
		List {
			if auth.isAuthenticated {
				accountSection
				groupsSection
				Section {
					Button("Sign Out", role: .destructive) {
						showingSignOut = true
					}
				}
			} else {
				guestSection
			}
		}
		.navigationTitle("Profile")
		.task {
			if auth.isAuthenticated {
				await groups.refresh()
				await auth.loadProfile()
			}
		}
		.sheet(item: $selectedGroup) { group in
			GroupDetailView(group: group)
		}
		.sheet(isPresented: $showingAuth) {
			AuthView()
		}
		.alert("New group", isPresented: $showingCreateGroup) {
			TextField("Group name", text: $newGroupName)
			Button("Create") {
				let name = newGroupName.trimmingCharacters(in: .whitespaces)
				guard !name.isEmpty else { return }
				Task { try? await groups.createGroup(name: name) }
			}
			Button("Cancel", role: .cancel) {}
		}
		.confirmationDialog(
			"Sign out?",
			isPresented: $showingSignOut,
			titleVisibility: .visible
		) {
			Button("Sign Out", role: .destructive) {
				Task { await auth.signOut() }
			}
			Button("Cancel", role: .cancel) {}
		}
	}

	private var guestSection: some View {
		Section {
			HStack(spacing: 14) {
				ZStack {
					Circle()
						.fill(Color.accentColor.opacity(0.2))
						.frame(width: 56, height: 56)
					Image(systemName: "iphone")
						.font(.title2)
						.foregroundStyle(Color.accentColor)
				}
				VStack(alignment: .leading, spacing: 4) {
					Text("On this iPhone")
						.font(.headline)
					Text("You're using GeoRemind without an account.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
			}
			.padding(.vertical, 4)

			Text(
				"Reminders stay on this device. Sign in to sync across devices, share with groups, and recover your pins if you switch devices."
			)
			.font(.footnote)
			.foregroundStyle(.secondary)

			Button {
				showingAuth = true
			} label: {
				Text("Sign In")
					.fontWeight(.semibold)
					.frame(maxWidth: .infinity)
			}
		}
	}

	private var accountSection: some View {
		Section {
			HStack(spacing: 14) {
				avatar
				VStack(alignment: .leading, spacing: 4) {
					Text(auth.profile?.username ?? "GeoRemind user")
						.font(.headline)
					if let email = auth.email {
						Text(email)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(.vertical, 4)

			if isEditingUsername {
				TextField("Username", text: $editedUsername)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
				Button("Save username") {
					Task {
						let ok = await auth.updateUsername(
							editedUsername.trimmingCharacters(
								in: .whitespaces
							)
						)
						if ok { isEditingUsername = false }
					}
				}
				.disabled(
					editedUsername.trimmingCharacters(in: .whitespaces)
						.count < 3
				)
			} else {
				Button("Change username") {
					editedUsername = auth.profile?.username ?? ""
					isEditingUsername = true
				}
			}

			if let message = auth.errorMessage, isEditingUsername,
				!message.isEmpty
			{
				Text(message)
					.font(.footnote)
					.foregroundStyle(.red)
			}
		}
	}

	private var groupsSection: some View {
		Section("Groups") {
			if groups.groups.isEmpty {
				Text("Create a group to share reminders with friends.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}

			ForEach(groups.groups) { group in
				Button {
					selectedGroup = group
				} label: {
					HStack {
						Image(systemName: "person.2.fill")
							.foregroundStyle(Color.accentColor)
						VStack(alignment: .leading, spacing: 2) {
							Text(group.name)
								.foregroundStyle(.primary)
							Text(
								group.isOwnedByCurrentUser
									? "Owner" : "Member"
							)
							.font(.caption)
							.foregroundStyle(.secondary)
						}
						Spacer()
						Image(systemName: "chevron.right")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
			}

			Button {
				newGroupName = ""
				showingCreateGroup = true
			} label: {
				Label("New Group", systemImage: "plus")
			}
		}
	}

	private var avatar: some View {
		let letter =
			(auth.profile?.username ?? "?").prefix(1).uppercased()
		return ZStack {
			Circle()
				.fill(Color.accentColor.opacity(0.2))
				.frame(width: 56, height: 56)
			Text(letter)
				.font(.title2.bold())
				.foregroundStyle(Color.accentColor)
		}
	}
}

#Preview {
	NavigationStack {
		Profile()
	}
	.environment(AuthService.shared)
	.environment(GroupStore.shared)
}
