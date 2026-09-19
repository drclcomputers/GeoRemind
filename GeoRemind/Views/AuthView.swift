//
//  AuthView.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import AuthenticationServices
import SwiftUI

struct AuthView: View {
	@Environment(AuthService.self) private var auth
	@Environment(\.dismiss) private var dismiss
	@Environment(\.webAuthenticationSession) private
		var webAuthenticationSession

	@State private var mode: Mode = .signIn
	@State private var email = ""
	@State private var password = ""
	@State private var username = ""
	@State private var isWorking = false
	@FocusState private var focusedField: Field?

	private enum Mode {
		case signIn, signUp
	}

	private enum Field {
		case username, email, password
	}

	var body: some View {
		@Bindable var auth = auth

		NavigationStack {
			ScrollView {
				VStack(spacing: 20) {
					Spacer(minLength: 40)

					HStack(spacing: 8) {
						Text("GeoRemind")
							.font(.custom("ReemKufiFun-Regular_Bold", size: 34))
						Image(systemName: "mappin")
							.font(.system(size: 28))
							.rotationEffect(.degrees(10))
					}

					Text(
						mode == .signIn
							? "Sign in to sync your reminders"
							: "Create an account"
					)
					.font(.title3)
					.foregroundStyle(.secondary)

					VStack(spacing: 12) {
						if mode == .signUp {
							TextField("Username", text: $username)
								.textInputAutocapitalization(.never)
								.autocorrectionDisabled()
								.textContentType(.username)
								.textFieldStyle(AuthFieldStyle())
								.focused($focusedField, equals: .username)
								.submitLabel(.next)
								.onSubmit { focusedField = .email }
						}

						TextField("Email", text: $email)
							.textInputAutocapitalization(.never)
							.autocorrectionDisabled()
							.keyboardType(.emailAddress)
							.textContentType(.emailAddress)
							.textFieldStyle(AuthFieldStyle())
							.focused($focusedField, equals: .email)
							.submitLabel(.next)
							.onSubmit { focusedField = .password }

						SecureField("Password", text: $password)
							.textContentType(
								mode == .signIn ? .password : .newPassword
							)
							.textFieldStyle(AuthFieldStyle())
							.focused($focusedField, equals: .password)
							.submitLabel(.go)
							.onSubmit { focusedField = nil }

						if mode == .signUp {
							PasswordChecklist(password: password)
						}
					}
					.padding(.horizontal, 32)

					if let message = auth.infoMessage, !message.isEmpty {
						Text(message)
							.font(.subheadline)
							.foregroundStyle(.primary)
							.multilineTextAlignment(.center)
							.padding(12)
							.frame(maxWidth: .infinity)
							.background(
								Color.accentColor.opacity(0.12),
								in: RoundedRectangle(cornerRadius: 12)
							)
							.padding(.horizontal, 32)
					}

					if let message = auth.errorMessage, !message.isEmpty {
						Text(message)
							.font(.subheadline)
							.foregroundStyle(.red)
							.multilineTextAlignment(.center)
							.padding(12)
							.frame(maxWidth: .infinity)
							.background(
								Color.red.opacity(0.08),
								in: RoundedRectangle(cornerRadius: 12)
							)
							.padding(.horizontal, 32)
					}

					Button {
						guard !isWorking else { return }
						isWorking = true
						Task {
							if mode == .signIn {
								await auth.signIn(
									email: email,
									password: password
								)
							} else {
								await auth.signUp(
									email: email,
									password: password,
									username: username
								)
							}
							isWorking = false
							if auth.isAuthenticated { dismiss() }
						}
					} label: {
						Text(
							isWorking
								? "Please wait…"
								: (mode == .signIn
									? "Sign In" : "Create Account")
						)
						.fontWeight(.semibold)
						.frame(maxWidth: .infinity)
						.padding()
						.background(Color.accentColor, in: Capsule())
						.foregroundStyle(.white)
					}
					.disabled(isWorking || !canSubmit)
					.padding(.horizontal, 32)

					Button {
						withAnimation {
							mode = mode == .signIn ? .signUp : .signIn
							auth.errorMessage = nil
							auth.infoMessage = nil
						}
					} label: {
						Text(
							mode == .signIn
								? "Don't have an account? Sign up"
								: "Already have an account? Sign in"
						)
						.font(.footnote)
					}

					HStack {
						Rectangle().frame(height: 1).foregroundStyle(
							.quaternary
						)
						Text("or")
							.font(.footnote)
							.foregroundStyle(.secondary)
						Rectangle().frame(height: 1).foregroundStyle(
							.quaternary
						)
					}
					.padding(.horizontal, 32)

					Button {
						startOAuth(google: true)
					} label: {
						Label {
							Text("Continue with Google")
								.fontWeight(.semibold)
								.foregroundStyle(Color(.systemBackground))
						} icon: {
							Image("google")
								.resizable()
								.scaledToFit()
								.frame(width: 20, height: 20)
						}
						.frame(maxWidth: .infinity)
						.padding()
						.background(Color.primary, in: Capsule())
					}
					.padding(.horizontal, 32)

					Button {
						startOAuth(google: false)
					} label: {
						Label {
							Text("Continue with Facebook")
								.fontWeight(.semibold)
						} icon: {
							Image("facebook")
								.resizable()
								.scaledToFit()
								.frame(width: 20, height: 20)
						}
						.frame(maxWidth: .infinity)
						.padding()
						.background(
							Color(
								red: 24 / 255,
								green: 119 / 255,
								blue: 242 / 255
							),
							in: Capsule()
						)
						.foregroundStyle(.white)
					}
					.padding(.horizontal, 32)

					Spacer(minLength: 40)
				}
				.frame(maxWidth: .infinity)
			}
			.scrollDismissesKeyboard(.interactively)
			.scrollIndicators(.hidden)
			.navigationTitle("Sign In")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Not now") { dismiss() }
				}
			}
			.onChange(of: auth.isAuthenticated) { _, signedIn in
				if signedIn { dismiss() }
			}
		}
	}

	private func startOAuth(google: Bool) {
		Task {
			let launch: (URL) async throws -> URL = { url in
				try await webAuthenticationSession.authenticate(
					using: url,
					callbackURLScheme: SupabaseConfig.oauthScheme
				)
			}
			if google {
				await auth.signInWithGoogle(launchFlow: launch)
			} else {
				await auth.signInWithFacebook(launchFlow: launch)
			}
			if auth.isAuthenticated {
				dismiss()
			}
		}
	}

	private var canSubmit: Bool {
		let mail = email.contains("@") && email.contains(".")
		if mode == .signUp {
			return mail && PasswordRules.isValid(password)
				&& username.trimmingCharacters(in: .whitespaces).count >= 3
		}
		return mail && password.count >= 6
	}
}

private enum PasswordRules {
	static func check(_ password: String) -> (
		length: Bool, upper: Bool, lower: Bool, digit: Bool, symbol: Bool
	) {
		(
			password.count >= 8,
			password.contains { $0.isUppercase && $0.isLetter },
			password.contains { $0.isLowercase && $0.isLetter },
			password.contains { $0.isNumber },
			password.contains {
				!$0.isLetter && !$0.isNumber && !$0.isWhitespace
			}
		)
	}

	static func isValid(_ password: String) -> Bool {
		let rules = check(password)
		return rules.length && rules.upper && rules.lower && rules.digit
			&& rules.symbol
	}
}

private struct PasswordChecklist: View {
	let password: String

	var body: some View {
		let rules = PasswordRules.check(password)
		VStack(alignment: .leading, spacing: 6) {
			ruleRow(loc("At least 8 characters"), ok: rules.length)
			ruleRow(loc("One uppercase letter"), ok: rules.upper)
			ruleRow(loc("One lowercase letter"), ok: rules.lower)
			ruleRow(loc("One number"), ok: rules.digit)
			ruleRow(loc("One symbol (!@#$…)"), ok: rules.symbol)
		}
		.font(.footnote)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.top, 4)
	}

	private func ruleRow(_ text: String, ok: Bool) -> some View {
		HStack(spacing: 8) {
			Image(systemName: ok ? "checkmark.circle.fill" : "circle")
				.foregroundStyle(ok ? Color.green : Color.secondary)
			Text(text)
				.foregroundStyle(ok ? Color.primary : Color.secondary)
		}
	}
}

private struct AuthFieldStyle: TextFieldStyle {
	func _body(configuration: TextField<Self._Label>) -> some View {
		configuration
			.padding(14)
			.background(
				Color(.secondarySystemBackground),
				in: RoundedRectangle(cornerRadius: 12)
			)
	}
}

#Preview {
	AuthView()
		.environment(AuthService.shared)
}
