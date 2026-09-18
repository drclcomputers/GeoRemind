//
//  UserProfile.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import Foundation

struct UserProfile: Identifiable, Codable, Equatable, Hashable {
	var id: UUID
	var username: String
	var avatarUrl: String?
	var createdAt: Date?
}

struct GeoGroup: Identifiable, Codable, Equatable, Hashable {
	var id: UUID
	var name: String
	var ownerId: UUID
	var createdAt: Date?

	var isOwnedByCurrentUser: Bool {
		ownerId == AuthService.shared.userId
	}

	func isOwned(by userId: UUID?) -> Bool {
		guard let userId else { return false }
		return ownerId == userId
	}
}

struct GroupMember: Identifiable, Equatable, Hashable {
	var groupId: UUID
	var userId: UUID
	var role: String
	var joinedAt: Date?
	var username: String
	var avatarUrl: String?

	var id: UUID { userId }
	var isOwner: Bool { role == "owner" }
}

struct GroupMemberRow: Decodable {
	var groupId: UUID
	var userId: UUID
	var role: String
	var joinedAt: Date?
	var profiles: MemberProfileEmbed?

	struct MemberProfileEmbed: Decodable {
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

struct GroupInsert: Encodable {
	var name: String
	var ownerId: UUID
}

struct GroupMemberInsert: Encodable {
	var groupId: UUID
	var userId: UUID
	var role: String
}

struct GroupInvite: Identifiable, Codable, Equatable, Hashable {
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

struct GroupInviteInsert: Encodable {
	var groupId: UUID
	var code: String
	var createdBy: UUID
	var expiresAt: Date
}

struct JoinGroupParams: Encodable {
	var invite_code: String
}
