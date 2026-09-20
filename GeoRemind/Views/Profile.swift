//
//  Profile.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import PhotosUI
import SwiftUI
import UIKit

struct Profile: View {
	@Environment(AuthService.self) private var auth
	@Environment(GroupStore.self) private var groups
	@Environment(NetworkMonitor.self) private var network

	@State private var editedUsername = ""
	@State private var isEditingUsername = false
	@State private var showingCreateGroup = false
	@State private var newGroupName = ""
	@State private var selectedGroup: GeoGroup?
	@State private var showingAuth = false
	@State private var showingSettings = false
	@State private var avatarItem: PhotosPickerItem?
	@State private var isUploadingAvatar = false
	@State private var inviteCode = ""

	var body: some View {
		List {
			if !network.isOnline {
				Section {
					Label {
						VStack(alignment: .leading, spacing: 4) {
							Text("You're offline.")
							Text(
								"Reminders still work on this iPhone. Groups and sync need a connection."
							)
							.font(.footnote)
							.foregroundStyle(.secondary)
						}
					} icon: {
						Image(systemName: "wifi.slash")
							.foregroundStyle(.orange)
					}
					.padding(.vertical, 4)
				}
			}
			if auth.isAuthenticated {
				accountSection
				groupsSection
			} else if auth.isOfflineAccount {
				offlineSection
			} else {
				guestSection
			}
		}
		.navigationTitle("Profile")
		.settingsAccess(isPresented: $showingSettings)
		.onChange(of: avatarItem) { _, item in
			guard let item else { return }
			Task { await uploadAvatar(item) }
		}
		.task {
			if auth.isAuthenticated, NetworkMonitor.shared.isOnline {
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

	private var offlineSection: some View {
		Section {
			HStack(spacing: 14) {
				ZStack {
					Circle()
						.fill(Color.accentColor.opacity(0.2))
						.frame(width: 56, height: 56)
					Image(systemName: "wifi.slash")
						.font(.title2)
						.foregroundStyle(Color.accentColor)
				}
				VStack(alignment: .leading, spacing: 4) {
					Text(
						auth.cachedAccount?.username
							?? auth.email
							?? "GeoRemind user"
					)
					.font(.headline)
					Text("You're offline.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
			}
			.padding(.vertical, 4)

			Text(
				"Reminders still work on this iPhone. Groups and sync need a connection."
			)
			.font(.footnote)
			.foregroundStyle(.secondary)
		}
	}

	private var accountSection: some View {
		Section {
			HStack(spacing: 14) {
				PhotosPicker(selection: $avatarItem, matching: .images) {
					avatar
				}
				.buttonStyle(.plain)
				.disabled(isUploadingAvatar)
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

			if let message = auth.errorMessage,
				isEditingUsername || isUploadingAvatar, !message.isEmpty
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

			HStack {
				TextField("Invite code", text: $inviteCode)
					.textInputAutocapitalization(.characters)
					.autocorrectionDisabled()
					.font(.body.monospaced())
				Button("Join") {
					let code = inviteCode
					inviteCode = ""
					Task { await groups.join(code: code) }
				}
				.disabled(
					inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
				)
			}

			if let message = groups.infoMessage, !message.isEmpty {
				Text(message)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			if let message = groups.errorMessage, !message.isEmpty {
				Text(message)
					.font(.footnote)
					.foregroundStyle(.red)
			}
		}
	}

	private var avatar: some View {
		ZStack(alignment: .bottomTrailing) {
			Group {
				if let urlString = auth.profile?.avatarUrl,
					let url = URL(string: urlString)
				{
					AsyncImage(url: url) { phase in
						switch phase {
						case .success(let image):
							image
								.resizable()
								.scaledToFill()
						default:
							avatarPlaceholder
						}
					}
				} else {
					avatarPlaceholder
				}
			}
			.frame(width: 56, height: 56)
			.clipShape(Circle())
			.overlay {
				if isUploadingAvatar {
					Circle().fill(.black.opacity(0.35))
					ProgressView()
						.tint(.white)
				}
			}

			Image(systemName: "camera.fill")
				.font(.system(size: 9, weight: .bold))
				.foregroundStyle(.white)
				.padding(5)
				.background(Color.accentColor, in: Circle())
				.offset(x: 2, y: 2)
		}
		.accessibilityLabel("Change profile photo")
	}

	private var avatarPlaceholder: some View {
		let letter =
			(auth.profile?.username ?? "?").prefix(1).uppercased()
		return ZStack {
			Circle()
				.fill(Color.accentColor.opacity(0.2))
			Text(letter)
				.font(.title2.bold())
				.foregroundStyle(Color.accentColor)
		}
	}

	private func uploadAvatar(_ item: PhotosPickerItem) async {
		isUploadingAvatar = true
		defer {
			isUploadingAvatar = false
			avatarItem = nil
		}
		do {
			guard let data = try await item.loadTransferable(type: Data.self),
				let jpeg = compressedJPEG(from: data)
			else { return }
			_ = await auth.updateAvatar(imageData: jpeg)
		} catch {
			auth.errorMessage = "Couldn't read that photo."
		}
	}

	private func compressedJPEG(from data: Data) -> Data? {
		guard let image = UIImage(data: data) else { return nil }
		let maxDimension: CGFloat = 512
		let longest = max(image.size.width, image.size.height)
		let scale = min(1, maxDimension / longest)
		let size = CGSize(
			width: image.size.width * scale,
			height: image.size.height * scale
		)
		let renderer = UIGraphicsImageRenderer(size: size)
		let rendered = renderer.image { _ in
			image.draw(in: CGRect(origin: .zero, size: size))
		}
		return rendered.jpegData(compressionQuality: 0.8)
	}
}

#Preview {
	NavigationStack {
		Profile()
	}
	.environment(AuthService.shared)
	.environment(GroupStore.shared)
	.environment(AppSettings.shared)
	.environment(NetworkMonitor.shared)
}
