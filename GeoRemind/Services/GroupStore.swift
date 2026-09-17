//
//  GroupStore.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class GroupStore {
	static let shared = GroupStore()

	var groups: [GeoGroup] = []
	var membersByGroup: [UUID: [GroupMember]] = [:]
	var isLoading = false
	var errorMessage: String?

	private init() {}
	
	func clear() {
		groups = []
		membersByGroup = [:]
		errorMessage = nil
	}

	func refresh() async {
		isLoading = true
		defer { isLoading = false }
		do {
			groups =
				try await supabase
				.from("groups")
				.select()
				.order("created_at", ascending: false)
				.execute()
				.value
			errorMessage = nil
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func createGroup(name: String) async throws {
		guard let ownerId = AuthService.shared.userId else {
			throw StoreError.notSignedIn
		}
		let created: GeoGroup =
			try await supabase
			.from("groups")
			.insert(GroupInsert(name: name, ownerId: ownerId))
			.select()
			.single()
			.execute()
			.value
		groups.insert(created, at: 0)
	}

	func deleteGroup(_ group: GeoGroup) async {
		groups.removeAll { $0.id == group.id }
		membersByGroup[group.id] = nil
		try? await supabase
			.from("groups")
			.delete()
			.eq("id", value: group.id)
			.execute()
	}

	func loadMembers(for groupId: UUID) async {
		do {
			let rows: [GroupMemberRow] =
				try await supabase
				.from("group_members")
				.select(
					"group_id, user_id, role, joined_at, profiles(username, avatar_url)"
				)
				.eq("group_id", value: groupId)
				.execute()
				.value
			membersByGroup[groupId] = rows.map { $0.asMember() }
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func addMember(username: String, to groupId: UUID) async throws {
		let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }

		let matches: [UserProfile] =
			try await supabase
			.from("profiles")
			.select()
			.eq("username", value: trimmed)
			.limit(1)
			.execute()
			.value

		guard let user = matches.first else {
			throw GroupError.userNotFound
		}

		try await supabase
			.from("group_members")
			.insert(
				GroupMemberInsert(
					groupId: groupId,
					userId: user.id,
					role: "member"
				)
			)
			.execute()

		await loadMembers(for: groupId)
	}

	func removeMember(_ member: GroupMember) async {
		membersByGroup[member.groupId]?.removeAll { $0.userId == member.userId }
		try? await supabase
			.from("group_members")
			.delete()
			.eq("group_id", value: member.groupId)
			.eq("user_id", value: member.userId)
			.execute()
	}

	func leave(_ group: GeoGroup) async {
		guard let userId = AuthService.shared.userId else { return }
		groups.removeAll { $0.id == group.id }
		try? await supabase
			.from("group_members")
			.delete()
			.eq("group_id", value: group.id)
			.eq("user_id", value: userId)
			.execute()
	}
}

enum GroupError: LocalizedError {
	case userNotFound

	var errorDescription: String? {
		switch self {
		case .userNotFound:
			return "No user with that username."
		}
	}
}
