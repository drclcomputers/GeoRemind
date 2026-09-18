//
//  GroupDetailView.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import SwiftUI

struct GroupDetailView: View {
	let group: GeoGroup

	@Environment(GroupStore.self) private var groups
	@Environment(\.dismiss) private var dismiss

	@State private var isCreatingInvite = false
	@State private var inviteError: String?
	@State private var showingDelete = false

	private var members: [GroupMember] {
		groups.membersByGroup[group.id] ?? []
	}

	private var invites: [GroupInvite] {
		groups.invitesByGroup[group.id] ?? []
	}

	var body: some View {
		NavigationStack {
			List {
				Section("Members") {
					ForEach(members) { member in
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(member.username)
								Text(member.isOwner ? "Owner" : "Member")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Spacer()
							if group.isOwnedByCurrentUser, !member.isOwner {
								Button("Remove", role: .destructive) {
									Task {
										await groups.removeMember(member)
									}
								}
								.font(.caption)
							}
						}
					}
				}

				if group.isOwnedByCurrentUser {
					Section {
						Button {
							isCreatingInvite = true
							Task {
								do {
									_ = try await groups.createInvite(
										for: group.id
									)
									inviteError = nil
								} catch {
									inviteError = error.localizedDescription
								}
								isCreatingInvite = false
							}
						} label: {
							Label(
								isCreatingInvite
									? "Creating…" : "New invite code",
								systemImage: "key"
							)
						}
						.disabled(isCreatingInvite)

						ForEach(invites) { invite in
							VStack(alignment: .leading, spacing: 6) {
								HStack {
									Text(invite.code)
										.font(.title3.monospaced())
										.textSelection(.enabled)
									Spacer()
									if invite.isExpired {
										Text("Expired")
											.font(.caption)
											.foregroundStyle(.secondary)
									} else {
										Text("\(invite.useCount) joined")
											.font(.caption)
											.foregroundStyle(.secondary)
									}
								}
								ShareLink(
									item:
										"Join my GeoRemind group \"\(group.name)\" with code \(invite.code)!"
								) {
									Label(
										"Share",
										systemImage: "square.and.arrow.up"
									)
								}
								.buttonStyle(.borderless)
							}
							.swipeActions(
								edge: .trailing,
								allowsFullSwipe: true
							) {
								Button("Revoke", role: .destructive) {
									Task {
										await groups.revokeInvite(invite)
									}
								}
							}
						}

						if let inviteError {
							Text(inviteError)
								.font(.footnote)
								.foregroundStyle(.red)
						}
					} header: {
						Text("Invites")
					} footer: {
						Text(
							"Share the code. People type it in Profile to join. Codes expire after 7 days. Swipe a code to revoke it."
						)
					}

					Section {
						Button("Delete group", role: .destructive) {
							showingDelete = true
						}
					}
				} else {
					Section {
						Button("Leave group", role: .destructive) {
							Task {
								await groups.leave(group)
								dismiss()
							}
						}
					}
				}
			}
			.navigationTitle(group.name)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
			.task {
				await groups.loadMembers(for: group.id)
				if group.isOwnedByCurrentUser {
					await groups.loadInvites(for: group.id)
				}
			}
			.confirmationDialog(
				"Delete this group?",
				isPresented: $showingDelete,
				titleVisibility: .visible
			) {
				Button("Delete", role: .destructive) {
					Task {
						await groups.deleteGroup(group)
						dismiss()
					}
				}
				Button("Cancel", role: .cancel) {}
			}
		}
	}
}
