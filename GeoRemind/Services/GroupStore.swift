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
	var invitesByGroup: [UUID: [GroupInvite]] = [:]
	var isLoading = false
	var errorMessage: String?
	var infoMessage: String?

	private static let pendingInviteKey = "georemind.pendingInviteCode"

	private init() {}

	func clear() {
		groups = []
		membersByGroup = [:]
		invitesByGroup = [:]
		errorMessage = nil
		infoMessage = nil
	}

	func refresh() async {
		guard AuthService.shared.isAuthenticated else {
			clear()
			return
		}
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

	func createInvite(for groupId: UUID) async throws -> GroupInvite {
		guard let userId = AuthService.shared.userId else {
			throw StoreError.notSignedIn
		}
		let invite = GroupInviteInsert(
			groupId: groupId,
			code: Self.makeCode(),
			createdBy: userId,
			expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 7)
		)
		let created: GroupInvite =
			try await supabase
			.from("group_invites")
			.insert(invite)
			.select()
			.single()
			.execute()
			.value
		invitesByGroup[groupId, default: []].insert(created, at: 0)
		return created
	}

	func loadInvites(for groupId: UUID) async {
		do {
			let rows: [GroupInvite] =
				try await supabase
				.from("group_invites")
				.select()
				.eq("group_id", value: groupId)
				.order("created_at", ascending: false)
				.execute()
				.value
			invitesByGroup[groupId] = rows
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func revokeInvite(_ invite: GroupInvite) async {
		invitesByGroup[invite.groupId]?.removeAll { $0.id == invite.id }
		try? await supabase
			.from("group_invites")
			.delete()
			.eq("id", value: invite.id)
			.execute()
	}

	func handleInviteURL(_ url: URL) async {
		guard let code = Self.code(from: url) else { return }
		await join(code: code)
	}

	func join(code: String) async {
		let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
			.uppercased()
		guard !normalized.isEmpty else { return }
		errorMessage = nil
		infoMessage = nil

		guard AuthService.shared.isAuthenticated else {
			UserDefaults.standard.set(normalized, forKey: Self.pendingInviteKey)
			infoMessage = loc("Sign in to join the group.")
			return
		}

		do {
			let groupId: UUID =
				try await supabase
				.rpc(
					"join_group_with_code",
					params: JoinGroupParams(invite_code: normalized)
				)
				.execute()
				.value
			UserDefaults.standard.removeObject(forKey: Self.pendingInviteKey)
			await refresh()
			await loadMembers(for: groupId)
			infoMessage = loc("You joined the group.")
		} catch {
			errorMessage = friendlyJoinError(error)
		}
	}

	func redeemPendingInvite() async {
		guard
			let code = UserDefaults.standard.string(
				forKey: Self.pendingInviteKey
			)
		else { return }
		await join(code: code)
	}

	private static func makeCode() -> String {
		let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
		return String((0..<6).map { _ in alphabet.randomElement()! })
	}

	private static func code(from url: URL) -> String? {
		guard url.scheme == SupabaseConfig.oauthScheme else { return nil }
		if url.host == "join" {
			let trimmed = url.path.trimmingCharacters(
				in: CharacterSet(charactersIn: "/")
			)
			if !trimmed.isEmpty { return trimmed }
			if let code = URLComponents(
				url: url,
				resolvingAgainstBaseURL: false
			)?
			.queryItems?.first(where: { $0.name == "code" })?.value {
				return code
			}
		}
		return nil
	}

	private func friendlyJoinError(_ error: Error) -> String {
		let text = error.localizedDescription.lowercased()
		if text.contains("invalid") {
			return loc("That invite code isn't valid.")
		}
		if text.contains("expired") {
			return loc("That invite has expired.")
		}
		if text.contains("used") {
			return loc("That invite can't be used anymore.")
		}
		if text.contains("authenticated") {
			return loc("Sign in to join the group.")
		}
		return error.localizedDescription
	}

	func removeMember(_ member: GroupMember) async {
		membersByGroup[member.groupId]?.removeAll { $0.userId == member.userId }
		try? await supabase
			.from("group_members")
			.delete()
			.eq("group_id", value: member.groupId)
			.eq("user_id", value: member.userId)
			.execute()
		await ReminderStore.shared.refresh()
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
		await ReminderStore.shared.refresh()
	}
}
