//
//  UserProfile.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import Foundation

nonisolated struct UserProfile: Identifiable, Codable, Equatable, Hashable,
	Sendable
{
	var id: UUID
	var username: String
	var avatarUrl: String?
	var createdAt: Date?
}

nonisolated struct GeoGroup: Identifiable, Codable, Equatable, Hashable,
	Sendable
{
	var id: UUID
	var name: String
	var ownerId: UUID
	var createdAt: Date?

	@MainActor
	var isOwnedByCurrentUser: Bool {
		ownerId == AuthService.shared.userId
	}

	func isOwned(by userId: UUID?) -> Bool {
		guard let userId else { return false }
		return ownerId == userId
	}
}

nonisolated struct GroupMember: Identifiable, Equatable, Hashable, Sendable {
	var groupId: UUID
	var userId: UUID
	var role: String
	var joinedAt: Date?
	var username: String
	var avatarUrl: String?

	var id: UUID { userId }
	var isOwner: Bool { role == "owner" }
}

nonisolated struct GroupMemberRow: Decodable, Sendable {
	var groupId: UUID
	var userId: UUID
	var role: String
	var joinedAt: Date?
	var profiles: MemberProfileEmbed?

	nonisolated struct MemberProfileEmbed: Decodable, Sendable {
		var username: String?
		var avatarUrl: String?
	}

	func asMember() -> GroupMember {
		GroupMember(
			groupId: groupId,
			userId: userId,
			role: role,
			joinedAt: joinedAt,
			username: profiles?.username ?? "user",
			avatarUrl: profiles?.avatarUrl
		)
	}
}

nonisolated struct GroupInsert: Encodable, Sendable {
	var name: String
	var ownerId: UUID
}

nonisolated struct GroupMemberInsert: Encodable, Sendable {
	var groupId: UUID
	var userId: UUID
	var role: String
}

nonisolated struct GroupInvite: Identifiable, Codable, Equatable, Hashable,
	Sendable
{
	var id: UUID
	var groupId: UUID
	var code: String
	var createdBy: UUID
	var createdAt: Date?
	var expiresAt: Date?
	var maxUses: Int?
	var useCount: Int

	var shareURL: URL {
		URL(string: "georemind://join/\(code)")!
	}

	var isExpired: Bool {
		guard let expiresAt else { return false }
		return expiresAt < Date()
	}
}

nonisolated struct GroupInviteInsert: Encodable, Sendable {
	var groupId: UUID
	var code: String
	var createdBy: UUID
	var expiresAt: Date
}

nonisolated struct JoinGroupParams: Encodable, Sendable {
	var invite_code: String
}
