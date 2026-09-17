//
//  AuthService.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import AuthenticationServices
import Auth
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
	var infoMessage: String?

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
					let wasSignedIn = self.session != nil
					self.session = session
					self.isRestoringSession = false
					if session != nil {
						await loadProfile()
						await ReminderStore.shared.handleSignedIn()
						await GroupStore.shared.refresh()
					} else {
						self.profile = nil
						if wasSignedIn {
							ReminderStore.shared.handleSignedOut()
						}
						GroupStore.shared.clear()
					}
				}
			}
		}
	}

	func signUp(email: String, password: String, username: String) async {
		errorMessage = nil
		infoMessage = nil
		do {
			let response = try await supabase.auth.signUp(
				email: email,
				password: password,
				data: ["username": .string(username)],
				redirectTo: SupabaseConfig.oauthRedirectURL
			)
			if let session = response.session {
				self.session = session
			} else {
				infoMessage =
					"Account created. Check your email to confirm, then sign in."
			}
		} catch {
			errorMessage = Self.friendlyAuthError(error)
		}
	}

	func signIn(email: String, password: String) async {
		errorMessage = nil
		infoMessage = nil
		do {
			self.session = try await supabase.auth.signIn(
				email: email,
				password: password
			)
		} catch {
			errorMessage = Self.friendlyAuthError(error)
		}
	}

	func signInWithApple(result: Result<ASAuthorization, Error>) async {
		errorMessage = nil
		do {
			let authorization = try result.get()
			guard
				let credential = authorization.credential
					as? ASAuthorizationAppleIDCredential
			else {
				errorMessage = "Invalid Apple credential."
				return
			}
			guard
				let idToken = credential.identityToken.flatMap({
					String(data: $0, encoding: .utf8)
				})
			else {
				errorMessage = "Missing Apple identity token."
				return
			}

			try await supabase.auth.signInWithIdToken(
				credentials: .init(provider: .apple, idToken: idToken)
			)

			if let fullName = formattedName(credential.fullName) {
				try? await supabase.auth.update(
					user: UserAttributes(data: ["full_name": .string(fullName)])
				)
			}
		} catch {
			if (error as NSError).code == 1001 { return }
			if Self.isCancel(error) { return }
			errorMessage = Self.friendlyAuthError(error)
		}
	}

	func signInWithGoogle(
		launchFlow: @escaping (URL) async throws -> URL
	) async {
		await signInWithOAuth(provider: .google, launchFlow: launchFlow)
	}

	func signInWithFacebook(
		launchFlow: @escaping (URL) async throws -> URL
	) async {
		await signInWithOAuth(provider: .facebook, launchFlow: launchFlow)
	}

	private func signInWithOAuth(
		provider: Provider,
		launchFlow: @escaping (URL) async throws -> URL
	) async {
		errorMessage = nil
		infoMessage = nil
		do {
			self.session = try await supabase.auth.signInWithOAuth(
				provider: provider,
				redirectTo: SupabaseConfig.oauthRedirectURL,
				launchFlow: { url in
					try await launchFlow(url)
				}
			)
		} catch {
			if Self.isCancel(error) { return }
			errorMessage = Self.friendlyAuthError(error)
		}
	}

	func handleOpenURL(_ url: URL) async {
		guard url.scheme == SupabaseConfig.oauthScheme else { return }
		do {
			_ = try await supabase.auth.session(from: url)
		} catch {
			if Self.isCancel(error) || session != nil { return }
		}
	}

	func signOut() async {
		errorMessage = nil
		do {
			try await supabase.auth.signOut()
		} catch {
			errorMessage = Self.friendlyAuthError(error)
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
			errorMessage = Self.friendlyAuthError(error)
			return false
		}
	}

	func loadProfile() async {
		guard let userId else {
			profile = nil
			return
		}
		do {
			profile = try await supabase
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

	static func isCancel(_ error: Error) -> Bool {
		if error is CancellationError { return true }
		if let asError = error as? ASWebAuthenticationSessionError {
			return asError.code == .canceledLogin
		}
		let ns = error as NSError
		if ns.domain == ASWebAuthenticationSessionError.errorDomain,
			ns.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
		{
			return true
		}
		if ns.domain.contains("WebAuthenticationSession"), ns.code == 1 {
			return true
		}
		if ns.code == 1001 { return true }
		return false
	}

	static func friendlyAuthError(_ error: Error) -> String {
		if isCancel(error) { return "" }
		let text = error.localizedDescription
		let lower = text.lowercased()
		if lower.contains("invalid login") || lower.contains("invalid credentials")
		{
			return "Wrong email or password."
		}
		if lower.contains("already registered") || lower.contains("already exists")
		{
			return "An account with this email already exists. Try signing in."
		}
		if lower.contains("email not confirmed") || lower.contains("not confirmed")
		{
			return "Confirm your email first — check your inbox."
		}
		if lower.contains("password")
			&& (lower.contains("weak") || lower.contains("at least")
				|| lower.contains("pwned") || lower.contains("leaked")
				|| lower.contains("characters") || lower.contains("strength"))
		{
			return "Password is too weak. Use 8+ characters with upper, lower, a number and a symbol."
		}
		if lower.contains("unable to validate email")
			|| lower.contains("invalid email")
		{
			return "That email address doesn't look valid."
		}
		if lower.contains("signup") && lower.contains("disabled") {
			return "Email sign up is disabled in Supabase. Enable Email under Authentication → Providers."
		}
		if lower.contains("duplicate") || lower.contains("unique") {
			return "That username is taken."
		}
		if lower.contains("localhost") || lower.contains("redirect") {
			return "Couldn't finish sign in. Add georemind://auth-callback in Supabase Redirect URLs."
		}
		if lower.contains("webauthentication")
			|| lower.contains("authenticationservices")
			|| lower.contains("com.apple.")
		{
			return "Sign in was interrupted. Please try again."
		}
		if text.count > 120 || (lower.contains("error ") && lower.contains("(")) {
			return "Something went wrong. Please try again."
		}
		return text
	}

	private func formattedName(_ name: PersonNameComponents?) -> String? {
		guard let name else { return nil }
		let formatter = PersonNameComponentsFormatter()
		let value = formatter.string(from: name).trimmingCharacters(
			in: .whitespaces
		)
		return value.isEmpty ? nil : value
	}
}
