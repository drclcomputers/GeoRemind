//
//  KeyboardDismisser.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 17/09/2026.
//

import SwiftUI
import UIKit

private final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
	static let shared = KeyboardDismisser()
	private var isInstalled = false

	func install() {
		guard !isInstalled,
			let window = UIApplication.shared.connectedScenes
				.compactMap({ $0 as? UIWindowScene })
				.first?.windows.first(where: \.isKeyWindow)
		else { return }

		let tap = UITapGestureRecognizer(
			target: self,
			action: #selector(handleTap)
		)
		tap.cancelsTouchesInView = false
		tap.delegate = self
		window.addGestureRecognizer(tap)
		isInstalled = true
	}

	@objc private func handleTap() {
		UIApplication.shared.sendAction(
			#selector(UIResponder.resignFirstResponder),
			to: nil,
			from: nil,
			for: nil
		)
	}

	func gestureRecognizer(
		_ gestureRecognizer: UIGestureRecognizer,
		shouldRecognizeSimultaneouslyWith otherGestureRecognizer:
			UIGestureRecognizer
	) -> Bool {
		true
	}
}

extension View {
	func dismissesKeyboardOnTap() -> some View {
		onAppear { KeyboardDismisser.shared.install() }
	}
}
