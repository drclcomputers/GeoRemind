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

	@State private var usernameToAdd = ""
	@State private var isAdding = false
	@State private var addError: String?
	@State private var showingDelete = false

	private var members: [GroupMember] {
		groups.membersByGroup[group.id] ?? []
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
					Section("Add member") {
						TextField("Username", text: $usernameToAdd)
							.textInputAutocapitalization(.never)
							.autocorrectionDisabled()
						Button {
							let name = usernameToAdd.trimmingCharacters(
								in: .whitespaces
							)
							guard !name.isEmpty else { return }
							isAdding = true
							Task {
								do {
									try await groups.addMember(
										username: name,
										to: group.id
									)
									usernameToAdd = ""
									addError = nil
								} catch {
									addError = error.localizedDescription
								}
								isAdding = false
							}
						} label: {
							Text(isAdding ? "Adding…" : "Add")
						}
						.disabled(isAdding || usernameToAdd.isEmpty)

						if let addError {
							Text(addError)
								.font(.footnote)
								.foregroundStyle(.red)
						}
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
