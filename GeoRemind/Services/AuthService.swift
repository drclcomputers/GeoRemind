//
//  AuthService.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import Auth
import AuthenticationServices
import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AuthService {
	static let shared = AuthService()

	var session: Session?
	var profile: UserProfile?
	var isRestoringSession = true
	var errorMessage: String?

	var isAuthenticated: Bool { session != nil }

	var userId: UUID? { session?.user.id }

	var email: String? { session?.user.email }

	@ObservationIgnored
	private var authTask: Task<Void, Never>?

	private init() {}

	func start() {
		guard authTask == nil else { return }
		authTask = Task {
			for await (event, session) in supabase.auth.authStateChanges {
				guard !Task.isCancelled else { break }
				if [.initialSession, .signedIn, .signedOut, .userUpdated]
					.contains(event)
				{
					self.session = session
					self.isRestoringSession = false
					if session != nil {
						await loadProfile()
						await ReminderStore.shared.refresh()
						await GroupStore.shared.refresh()
						ReminderStore.shared.startRealtime()
					} else {
						self.profile = nil
						ReminderStore.shared.clear()
						GroupStore.shared.clear()
					}
				}
			}
		}
	}

	func signUp(email: String, password: String, username: String) async {
		errorMessage = nil
		do {
			let response = try await supabase.auth.signUp(
				email: email,
				password: password,
				data: ["username": .string(username)]
			)
			if response.session == nil {
				errorMessage =
					"Check your email to confirm the account, then sign in."
			}
		} catch {
			errorMessage = friendlyAuthError(error)
		}
	}

	func signIn(email: String, password: String) async {
		errorMessage = nil
		do {
			try await supabase.auth.signIn(email: email, password: password)
		} catch {
			errorMessage = friendlyAuthError(error)
		}
	}

	func signInWithGoogle() async {
		await signInWithOAuth(provider: .google)
	}

	func signInWithFacebook() async {
		await signInWithOAuth(provider: .facebook)
	}

	private func signInWithOAuth(provider: Provider) async {
		errorMessage = nil
		do {
			try await supabase.auth.signInWithOAuth(
				provider: provider,
				redirectTo: SupabaseConfig.oauthRedirectURL
			)
		} catch {
			errorMessage = friendlyAuthError(error)
		}
	}

	func handleOpenURL(_ url: URL) async {
		do {
			_ = try await supabase.auth.session(from: url)
		} catch {
			errorMessage = friendlyAuthError(error)
		}
	}

	func signOut() async {
		errorMessage = nil
		do {
			try await supabase.auth.signOut()
		} catch {
			errorMessage = friendlyAuthError(error)
		}
	}

	func updateUsername(_ username: String) async -> Bool {
		guard let userId else { return false }
		errorMessage = nil
		do {
			try await supabase
				.from("profiles")
				.update(["username": username])
				.eq("id", value: userId)
				.execute()
			await loadProfile()
			return true
		} catch {
			errorMessage = friendlyAuthError(error)
			return false
		}
	}

	func loadProfile() async {
		guard let userId else {
			profile = nil
			return
		}
		do {
			profile =
				try await supabase
				.from("profiles")
				.select()
				.eq("id", value: userId)
				.single()
				.execute()
				.value
		} catch {
			profile = nil
		}
	}

	private func formattedName(_ name: PersonNameComponents?) -> String? {
		guard let name else { return nil }
		let formatter = PersonNameComponentsFormatter()
		let value = formatter.string(from: name).trimmingCharacters(
			in: .whitespaces
		)
		return value.isEmpty ? nil : value
	}

	private func friendlyAuthError(_ error: Error) -> String {
		let text = error.localizedDescription
		if text.localizedCaseInsensitiveContains("invalid login") {
			return "Wrong email or password."
		}
		if text.localizedCaseInsensitiveContains("already registered") {
			return "An account with this email already exists."
		}
		if text.localizedCaseInsensitiveContains("duplicate")
			|| text.localizedCaseInsensitiveContains("unique")
		{
			return "That username is taken."
		}
		return text
	}
}
