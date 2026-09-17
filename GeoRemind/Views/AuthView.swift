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
					}
					.padding(.horizontal, 32)

					if let message = auth.errorMessage {
						Text(message)
							.font(.footnote)
							.foregroundStyle(.red)
							.multilineTextAlignment(.center)
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
						Task { await auth.signInWithGoogle() }
					} label: {
						Label("Continue with Google", systemImage: "globe")
							.fontWeight(.semibold)
							.frame(maxWidth: .infinity)
							.padding()
							.background(
								Color(.secondarySystemBackground),
								in: Capsule()
							)
					}
					.padding(.horizontal, 32)

					Button {
						Task { await auth.signInWithFacebook() }
					} label: {
						HStack(spacing: 8) {
							Text("f")
								.font(.title3.bold())
							Text("Continue with Facebook")
								.fontWeight(.semibold)
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
			.toolbar(.hidden, for: .navigationBar)
		}
	}

	private var canSubmit: Bool {
		let mail = !email.trimmingCharacters(in: .whitespaces).isEmpty
		let pass = password.count >= 6
		if mode == .signUp {
			return mail && pass
				&& username.trimmingCharacters(in: .whitespaces).count >= 3
		}
		return mail && pass
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
