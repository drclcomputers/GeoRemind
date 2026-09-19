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
import Storage
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
	var linkedProviders: [String] = []

	var isAuthenticated: Bool { session != nil }

	var userId: UUID? { session?.user.id }

	var email: String? { session?.user.email }

	func hasProvider(_ provider: String) -> Bool {
		linkedProviders.contains(provider)
			|| (session?.user.identities?.contains { $0.provider == provider }
				?? false)
	}

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
					if session != nil, !wasSignedIn {
						ReminderStore.shared.snapshotGuestPins()
					}
					self.session = session
					self.isRestoringSession = false
					if session != nil {
						await loadProfile()
						await reloadIdentities()
						await fillAvatarFromOAuthIfNeeded()
						if !wasSignedIn
							|| ReminderStore.shared.hasPendingGuestPins
						{
							await ReminderStore.shared.handleSignedIn()
						}
						if !wasSignedIn {
							await GroupStore.shared.refresh()
						}
					} else {
						self.profile = nil
						self.linkedProviders = []
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
		captureGuestPinsIfNeeded()
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
		captureGuestPinsIfNeeded()
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
		captureGuestPinsIfNeeded()
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
				_ = try? await supabase.auth.update(
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
		captureGuestPinsIfNeeded()
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

	func linkOAuth(
		provider: Provider,
		launchFlow: @escaping (URL) async throws -> URL
	) async {
		errorMessage = nil
		infoMessage = nil
		do {
			let oauthURL = try await identityAuthorizeURL(for: provider)
			let callback = try await launchFlow(oauthURL)
			_ = try await supabase.auth.session(from: callback)
			rememberLinked(provider.rawValue)
			_ = try? await supabase.auth.refreshSession()
			self.session = try await supabase.auth.session
			await reloadIdentities()
			rememberLinked(provider.rawValue)
			infoMessage = "Account linked."
		} catch {
			if Self.isCancel(error) { return }
			errorMessage = Self.friendlyAuthError(error)
		}
	}

	func deleteAccount(password: String) async -> Bool {
		guard let email else {
			errorMessage = "No email on this account."
			return false
		}
		errorMessage = nil
		infoMessage = nil
		do {
			_ = try await supabase.auth.signIn(email: email, password: password)
			try await finishDeletion()
			return true
		} catch {
			errorMessage = Self.friendlyAuthError(error)
			return false
		}
	}

	func deleteAccount(
		provider: Provider,
		launchFlow: @escaping (URL) async throws -> URL
	) async -> Bool {
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
			try await finishDeletion()
			return true
		} catch {
			if Self.isCancel(error) { return false }
			errorMessage = Self.friendlyAuthError(error)
			return false
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

	private func finishDeletion() async throws {
		if let userId {
			_ = try? await supabase.storage.from("avatars").remove(paths: [
				"\(userId.uuidString.lowercased())/avatar.jpg"
			])
		}
		try await supabase.rpc("delete_own_account").execute()
		try? await supabase.auth.signOut()
		session = nil
		profile = nil
		ReminderStore.shared.handleSignedOut()
		GroupStore.shared.clear()
	}

	private func identityAuthorizeURL(for provider: Provider) async throws
		-> URL
	{
		guard let token = session?.accessToken else {
			throw StoreError.notSignedIn
		}
		var components = URLComponents(
			url: SupabaseConfig.url.appendingPathComponent(
				"auth/v1/user/identities/authorize"
			),
			resolvingAgainstBaseURL: false
		)!
		components.queryItems = [
			URLQueryItem(name: "provider", value: provider.rawValue),
			URLQueryItem(
				name: "redirect_to",
				value: SupabaseConfig.oauthRedirectURL.absoluteString
			),
			URLQueryItem(name: "skip_http_redirect", value: "true"),
		]
		var request = URLRequest(url: components.url!)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse,
			(200...299).contains(http.statusCode)
		else {
			throw URLError(.badServerResponse)
		}
		struct Payload: Decodable { var url: String }
		let payload = try JSONDecoder().decode(Payload.self, from: data)
		guard let url = URL(string: payload.url) else {
			throw URLError(.badURL)
		}
		return url
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

	func updateAvatar(imageData: Data) async -> Bool {
		guard let userId else { return false }
		errorMessage = nil
		do {
			let path = "\(userId.uuidString.lowercased())/avatar.jpg"
			try await supabase.storage
				.from("avatars")
				.upload(
					path,
					data: imageData,
					options: FileOptions(
						contentType: "image/jpeg",
						upsert: true
					)
				)
			var publicURL = try supabase.storage
				.from("avatars")
				.getPublicURL(path: path)
			var items = URLComponents(
				url: publicURL,
				resolvingAgainstBaseURL: false
			)
			items?.queryItems = [
				URLQueryItem(
					name: "t",
					value: String(Int(Date().timeIntervalSince1970))
				)
			]
			if let stamped = items?.url {
				publicURL = stamped
			}
			try await supabase
				.from("profiles")
				.update(["avatar_url": publicURL.absoluteString])
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

	private func reloadIdentities() async {
		let fetched: [String]
		do {
			let user = try await supabase.auth.user()
			fetched = (user.identities ?? []).map(\.provider)
		} catch {
			fetched = (session?.user.identities ?? []).map(\.provider)
		}
		linkedProviders = Array(Set(linkedProviders + fetched)).sorted()
	}

	private func rememberLinked(_ provider: String) {
		if !linkedProviders.contains(provider) {
			linkedProviders = (linkedProviders + [provider]).sorted()
		}
	}

	private func fillAvatarFromOAuthIfNeeded() async {
		guard profile?.avatarUrl == nil, let userId else { return }
		let picture: String?
		if case .string(let value) = session?.user.userMetadata["picture"] {
			picture = value
		} else if case .string(let value) = session?.user.userMetadata[
			"avatar_url"
		] {
			picture = value
		} else {
			picture = nil
		}
		guard let picture, let url = URL(string: picture) else { return }
		do {
			try await supabase
				.from("profiles")
				.update(["avatar_url": url.absoluteString])
				.eq("id", value: userId)
				.execute()
			await loadProfile()
		} catch {}
	}

	static func isCancel(_ error: Error) -> Bool {
		if error is CancellationError { return true }
		if let asError = error as? ASWebAuthenticationSessionError {
			return asError.code == .canceledLogin
		}
		let ns = error as NSError
		if ns.domain == ASWebAuthenticationSessionError.errorDomain,
			ns.code
				== ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
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
		if lower.contains("invalid login")
			|| lower.contains("invalid credentials")
		{
			return loc("Wrong email or password.")
		}
		if lower.contains("already registered")
			|| lower.contains("already exists")
		{
			return loc(
				"An account with this email already exists. Try signing in."
			)
		}
		if lower.contains("email not confirmed")
			|| lower.contains("not confirmed")
		{
			return loc("Confirm your email first — check your inbox.")
		}
		if lower.contains("password")
			&& (lower.contains("weak") || lower.contains("at least")
				|| lower.contains("pwned") || lower.contains("leaked")
				|| lower.contains("characters") || lower.contains("strength"))
		{
			return loc(
				"Password is too weak. Use 8+ characters with upper, lower, a number and a symbol."
			)
		}
		if lower.contains("unable to validate email")
			|| lower.contains("invalid email")
		{
			return loc("That email address doesn't look valid.")
		}
		if lower.contains("direct deletion") || lower.contains("storage api") {
			return loc("Couldn't delete the account photo. Try again.")
		}
		if lower.contains("bucket") || lower.contains("not found")
			|| lower.contains("object") && lower.contains("404")
		{
			return loc(
				"Photo storage isn't set up. Create a public avatars bucket in Supabase."
			)
		}
		if lower.contains("duplicate") || lower.contains("unique") {
			return loc("That username is taken.")
		}
		if lower.contains("manual linking")
			|| lower.contains("linking is disabled")
		{
			return loc(
				"Manual linking is off. Enable it under Authentication → Sign In / Providers."
			)
		}
		if lower.contains("identity") && lower.contains("already") {
			return loc(
				"That Google or Facebook account is already linked to another user."
			)
		}
		if lower.contains("localhost") || lower.contains("redirect") {
			return loc(
				"Couldn't finish sign in. Add georemind://auth-callback in Supabase Redirect URLs."
			)
		}
		if lower.contains("webauthentication")
			|| lower.contains("authenticationservices")
			|| lower.contains("com.apple.")
		{
			return loc("Sign in was interrupted. Please try again.")
		}
		if text.count > 120 || (lower.contains("error ") && lower.contains("("))
		{
			return loc("Something went wrong. Please try again.")
		}
		return text
	}

	private func captureGuestPinsIfNeeded() {
		guard session == nil else { return }
		ReminderStore.shared.snapshotGuestPins()
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
