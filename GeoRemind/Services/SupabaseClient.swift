//
//  SupabaseClient.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import Foundation
import Supabase

enum SupabaseConfig {
	static let url = URL(string: "https://fzrjaufdclqbkvfaeycs.supabase.co")!
	static let anonKey = "sb_publishable_As9x_prAChIOEbIKtkz_0A_TILeYyX8"

	static let oauthScheme = "georemind"
	static let oauthRedirectURL = URL(string: "georemind://auth-callback")!
}

enum JSONCoders {
	static let decoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		decoder.dateDecodingStrategy = .custom { decoder in
			let container = try decoder.singleValueContainer()
			let string = try container.decode(String.self)
			if let date = fractionalISO8601.date(from: string)
				?? standardISO8601.date(from: string)
			{
				return date
			}
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "Invalid date: \(string)"
			)
		}
		return decoder
	}()

	static let encoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.keyEncodingStrategy = .convertToSnakeCase
		encoder.dateEncodingStrategy = .iso8601
		return encoder
	}()

	private static let fractionalISO8601: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	private static let standardISO8601: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter
	}()
}

let supabase = SupabaseClient(
	supabaseURL: SupabaseConfig.url,
	supabaseKey: SupabaseConfig.anonKey,
	options: SupabaseClientOptions(
		db: .init(
			encoder: JSONCoders.encoder,
			decoder: JSONCoders.decoder
		),
		auth: .init(
			redirectToURL: SupabaseConfig.oauthRedirectURL
		)
	)
)
