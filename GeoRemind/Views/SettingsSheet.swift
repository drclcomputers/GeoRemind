//
//  SettingsSheet.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 18/09/2026.
//

import Auth
import AuthenticationServices
import CoreLocation
import SwiftUI

struct SettingsSheet: View {
	@Environment(AppSettings.self) private var settings
	@Environment(AuthService.self) private var auth
	@Environment(\.dismiss) private var dismiss
	@Environment(\.openURL) private var openURL
	@Environment(\.webAuthenticationSession) private
		var webAuthenticationSession

	@State private var showingSignOut = false
	@State private var showingAuth = false
	@State private var showingDelete = false
	@State private var editingPlace: SavedPlaceKind?
	@State private var showingPlaceSearch = false
	@State private var placeSearchCoord: CLLocationCoordinate2D?
	@State private var placeSearchAddress = ""

	private var appVersion: String {
		let info = Bundle.main.infoDictionary
		let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
		let build = info?["CFBundleVersion"] as? String ?? "1"
		return "\(short) (\(build))"
	}

	var body: some View {
		@Bindable var settings = settings
		@Bindable var auth = auth

		NavigationStack {
			List {
				Section {
					Picker("Appearance", selection: $settings.appearance) {
						ForEach(AppAppearance.allCases) { mode in
							Text(mode.title).tag(mode)
						}
					}
					.pickerStyle(.segmented)
				} header: {
					Text("Appearance")
				} footer: {
					Text("System follows the appearance set on your iPhone.")
				}

				Section {
					Picker("Language", selection: $settings.language) {
						ForEach(AppLanguage.allCases) { lang in
							Text(lang.nativeName).tag(lang)
						}
					}
				} header: {
					Text("Language")
				} footer: {
					Text(
						"System uses the iPhone language. You can also change it in Settings → GeoRemind."
					)
				}

				Section {
					Picker("Units", selection: $settings.units) {
						ForEach(MeasureUnits.allCases) { unit in
							Text(unit.title).tag(unit)
						}
					}
					.pickerStyle(.segmented)
				} header: {
					Text("Distance")
				} footer: {
					Text(settings.units.caption)
				}

				Section {
					ForEach(SavedPlaceKind.allCases) { kind in
						Button {
							editingPlace = kind
						} label: {
							HStack {
								Label(kind.title, systemImage: kind.symbol)
								Spacer()
								Text(
									settings.place(for: kind)?.address
										?? "Not set"
								)
								.foregroundStyle(.secondary)
								.lineLimit(1)
							}
						}
					}
				} header: {
					Text("Places")
				} footer: {
					Text(
						"Used as one-tap locations when you add a reminder."
					)
				}

				Section("Account") {
					if auth.isAuthenticated {
						if let name = auth.profile?.username {
							LabeledContent("Signed in as", value: name)
						}
						if let email = auth.email {
							LabeledContent("Email", value: email)
						}
						Button("Sign Out", role: .destructive) {
							showingSignOut = true
						}
					} else {
						Button("Sign In") { showingAuth = true }
					}
				}

				if auth.isAuthenticated {
					let linked = auth.linkedProviders
					Section {
						linkedRow(
							title: "Google",
							linked: linked.contains("google")
						) {
							link(.google)
						}
						linkedRow(
							title: "Facebook",
							linked: linked.contains("facebook")
						) {
							link(.facebook)
						}
					} header: {
						Text("Connected accounts")
					} footer: {
						Text(
							"Link Google or Facebook while signed in so the same profile and photo are kept."
						)
					}
					.id(linked.joined(separator: ","))

					Section {
						Button("Delete Account", role: .destructive) {
							showingDelete = true
						}
					} footer: {
						Text(
							"This permanently deletes your reminders, groups, photo and login."
						)
					}
				}

				Section("System") {
					Button("Open iPhone Settings") {
						if let url = URL(
							string: UIApplication.openSettingsURLString
						) {
							openURL(url)
						}
					}
				}

				Section {
					LabeledContent("Version", value: appVersion)
				}

				if let message = auth.infoMessage, !message.isEmpty {
					Section {
						Text(message)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
				if let message = auth.errorMessage, !message.isEmpty {
					Section {
						Text(message)
							.font(.footnote)
							.foregroundStyle(.red)
					}
				}
			}
			.navigationTitle("Settings")
			.navigationBarTitleDisplayMode(.inline)
			.appAppearance(settings.appearance)
			.environment(\.locale, settings.resolvedLocale)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
			.sheet(isPresented: $showingAuth) {
				AuthView()
			}
			.sheet(isPresented: $showingDelete) {
				DeleteAccountSheet()
			}
			.sheet(isPresented: $showingPlaceSearch) {
				SearchSheet(
					selectedCoordinate: $placeSearchCoord,
					selectedAddress: $placeSearchAddress
				)
			}
			.onChange(of: showingPlaceSearch) { _, open in
				if !open, let kind = editingPlace, let coord = placeSearchCoord
				{
					let address =
						placeSearchAddress.isEmpty
						? kind.titleString : placeSearchAddress
					settings.setPlace(
						SavedPlace(
							address: address,
							latitude: coord.latitude,
							longitude: coord.longitude
						),
						for: kind
					)
					placeSearchCoord = nil
					placeSearchAddress = ""
					editingPlace = nil
				}
			}
			.confirmationDialog(
				editingPlace?.title ?? "Place",
				isPresented: Binding(
					get: { editingPlace != nil && !showingPlaceSearch },
					set: { if !$0 { editingPlace = nil } }
				),
				titleVisibility: .visible
			) {
				Button("Use Current Location") {
					let kind = editingPlace
					Task { await setPlaceFromCurrent(kind) }
				}
				Button("Search") {
					placeSearchCoord = nil
					placeSearchAddress = ""
					showingPlaceSearch = true
				}
				if let kind = editingPlace, settings.place(for: kind) != nil {
					Button("Clear", role: .destructive) {
						if let kind = editingPlace {
							settings.setPlace(nil, for: kind)
						}
						editingPlace = nil
					}
				}
				Button("Cancel", role: .cancel) {
					editingPlace = nil
				}
			}
			.confirmationDialog(
				"Sign out?",
				isPresented: $showingSignOut,
				titleVisibility: .visible
			) {
				Button("Sign Out", role: .destructive) {
					Task {
						await auth.signOut()
						dismiss()
					}
				}
				Button("Cancel", role: .cancel) {}
			}
		}
	}

	private func setPlaceFromCurrent(_ kind: SavedPlaceKind?) async {
		guard let kind else { return }
		GeofenceManager.shared.requestWhenInUseAuthorization()
		guard let coord = await getCurrentLocation() else {
			editingPlace = nil
			return
		}
		let address = await reverseAddress(for: coord)
		settings.setPlace(
			SavedPlace(
				address: address.isEmpty ? kind.titleString : address,
				latitude: coord.latitude,
				longitude: coord.longitude
			),
			for: kind
		)
		editingPlace = nil
	}

	private func linkedRow(
		title: String,
		linked: Bool,
		action: @escaping () -> Void
	) -> some View {
		HStack {
			Text(title)
			Spacer()
			if linked {
				Text("Linked")
					.foregroundStyle(.secondary)
			} else {
				Button("Link", action: action)
			}
		}
	}

	private func link(_ provider: Provider) {
		Task {
			await auth.linkOAuth(provider: provider, launchFlow: oauthLaunch)
		}
	}

	private func oauthLaunch(_ url: URL) async throws -> URL {
		try await webAuthenticationSession.authenticate(
			using: url,
			callbackURLScheme: SupabaseConfig.oauthScheme
		)
	}
}

struct DeleteAccountSheet: View {
	@Environment(AuthService.self) private var auth
	@Environment(\.dismiss) private var dismiss
	@Environment(AppSettings.self) private var settings
	@Environment(\.webAuthenticationSession) private
		var webAuthenticationSession

	@State private var understood = false
	@State private var typedEmail = ""
	@State private var typedDelete = ""
	@State private var password = ""
	@State private var isWorking = false

	private var emailMatches: Bool {
		typedEmail.trimmingCharacters(in: .whitespaces).lowercased()
			== (auth.email ?? "").lowercased()
	}

	private var deleteMatches: Bool {
		typedDelete.trimmingCharacters(in: .whitespaces) == "DELETE"
	}

	private var checksPass: Bool {
		understood && emailMatches && deleteMatches && !isWorking
	}

	private var hasPassword: Bool { auth.hasProvider("email") }
	private var hasGoogle: Bool { auth.hasProvider("google") }
	private var hasFacebook: Bool { auth.hasProvider("facebook") }

	var body: some View {
		@Bindable var auth = auth

		NavigationStack {
			Form {
				Section {
					Toggle(
						"I understand my reminders, groups and photo will be permanently deleted.",
						isOn: $understood
					)
				}

				Section {
					TextField("Your email", text: $typedEmail)
						.textInputAutocapitalization(.never)
						.keyboardType(.emailAddress)
						.autocorrectionDisabled()
				} footer: {
					Text("Type \(auth.email ?? loc("your email")) to confirm.")
				}

				Section {
					TextField("Type DELETE", text: $typedDelete)
						.textInputAutocapitalization(.characters)
						.autocorrectionDisabled()
				}

				if hasPassword {
					Section {
						SecureField("Password", text: $password)
						Button("Delete with password", role: .destructive) {
							runDelete {
								await auth.deleteAccount(password: password)
							}
						}
						.disabled(!checksPass || password.isEmpty)
					} footer: {
						Text("Confirms it's you, then deletes the account.")
					}
				}

				if hasGoogle || hasFacebook || !hasPassword {
					Section {
						if hasGoogle || (!hasPassword && !hasFacebook) {
							Button("Confirm with Google", role: .destructive) {
								runDelete {
									await auth.deleteAccount(
										provider: .google,
										launchFlow: oauthLaunch
									)
								}
							}
							.disabled(!checksPass)
						}
						if hasFacebook || (!hasPassword && !hasGoogle) {
							Button("Confirm with Facebook", role: .destructive)
							{
								runDelete {
									await auth.deleteAccount(
										provider: .facebook,
										launchFlow: oauthLaunch
									)
								}
							}
							.disabled(!checksPass)
						}
					} footer: {
						Text(
							"If you signed in with Google or Facebook, confirm with the same provider. No email is sent."
						)
					}
				}

				if let message = auth.infoMessage, !message.isEmpty {
					Section {
						Text(message).foregroundStyle(.secondary)
					}
				}
				if let message = auth.errorMessage, !message.isEmpty {
					Section {
						Text(message).foregroundStyle(.red)
					}
				}
			}
			.navigationTitle("Delete Account")
			.navigationBarTitleDisplayMode(.inline)
			.environment(\.locale, settings.resolvedLocale)
			.appAppearance(settings.appearance)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
		}
	}

	private func runDelete(_ action: @escaping () async -> Bool) {
		isWorking = true
		Task {
			let ok = await action()
			isWorking = false
			if ok { dismiss() }
		}
	}

	private func oauthLaunch(_ url: URL) async throws -> URL {
		try await webAuthenticationSession.authenticate(
			using: url,
			callbackURLScheme: SupabaseConfig.oauthScheme
		)
	}
}

extension View {
	func settingsAccess(isPresented: Binding<Bool>) -> some View {
		toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					isPresented.wrappedValue = true
				} label: {
					Image(systemName: "gearshape")
				}
				.accessibilityLabel("Settings")
			}
		}
		.sheet(isPresented: isPresented) {
			SettingsSheet()
		}
	}
}

private struct AppAppearanceModifier: ViewModifier {
	var appearance: AppAppearance
	@Environment(\.colorScheme) private var systemScheme

	func body(content: Content) -> some View {
		let scheme = appearance.colorScheme ?? systemScheme
		content
			.environment(\.colorScheme, scheme)
			.preferredColorScheme(appearance.colorScheme)
			.id(appearance)
	}
}

extension View {
	func appAppearance(_ appearance: AppAppearance) -> some View {
		modifier(AppAppearanceModifier(appearance: appearance))
	}
}
