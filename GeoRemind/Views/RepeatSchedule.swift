//
//  RepeatSchedule.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 20/09/2026.
//

import SwiftUI

nonisolated enum WeekdayMask {
	static let all = 0b1111111

	static func contains(_ mask: Int, isoDay: Int) -> Bool {
		let bits = mask == 0 ? all : mask
		return (bits & (1 << (isoDay - 1))) != 0
	}

	static func contains(_ mask: Int, date: Date) -> Bool {
		contains(mask, isoDay: isoDay(for: date))
	}

	static func toggling(_ mask: Int, isoDay: Int) -> Int {
		let current = mask == 0 ? all : mask
		let next = current ^ (1 << (isoDay - 1))
		return next == 0 ? current : next
	}

	static func isoDay(for date: Date) -> Int {
		let weekday = Calendar.current.component(.weekday, from: date)
		return weekday == 1 ? 7 : weekday - 1
	}

	static func shortLabel(isoDay: Int) -> String {
		let symbols = Calendar.current.veryShortWeekdaySymbols
		guard symbols.count == 7 else { return "\(isoDay)" }
		let sundayFirstIndex = isoDay == 7 ? 0 : isoDay
		return symbols[sundayFirstIndex]
	}

	static func summary(_ mask: Int) -> String {
		let bits = mask == 0 ? all : mask
		if bits == all { return loc("Every day") }
		let names = (1...7).compactMap { day -> String? in
			contains(bits, isoDay: day) ? shortLabel(isoDay: day) : nil
		}
		return names.joined(separator: " ")
	}
}

nonisolated enum DayMinutes {
	static func matches(from: Int?, to: Int?, date: Date = .now) -> Bool {
		guard let from, let to else { return true }
		let parts = Calendar.current.dateComponents(
			[.hour, .minute],
			from: date
		)
		let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
		if from <= to { return now >= from && now <= to }
		return now >= from || now <= to
	}

	static func label(_ minutes: Int) -> String {
		let hour = minutes / 60
		let minute = minutes % 60
		var parts = DateComponents()
		parts.hour = hour
		parts.minute = minute
		let date = Calendar.current.date(from: parts) ?? Date()
		return date.formatted(date: .omitted, time: .shortened)
	}

	static func binding(_ minutes: Binding<Int>) -> Binding<Date> {
		Binding(
			get: {
				let hour = minutes.wrappedValue / 60
				let minute = minutes.wrappedValue % 60
				return Calendar.current.date(
					from: DateComponents(hour: hour, minute: minute)
				) ?? Date()
			},
			set: { date in
				let parts = Calendar.current.dateComponents(
					[.hour, .minute],
					from: date
				)
				minutes.wrappedValue =
					(parts.hour ?? 0) * 60 + (parts.minute ?? 0)
			}
		)
	}
}

struct RepeatScheduleEditor: View {
	@Binding var repeats: Bool
	@Binding var weekdays: Int
	@Binding var restrictHours: Bool
	@Binding var fromMinutes: Int
	@Binding var toMinutes: Int

	var body: some View {
		Section {
			Picker("Repeat", selection: $repeats) {
				Text("Every time").tag(true)
				Text("Once").tag(false)
			}
			.pickerStyle(.segmented)

			HStack(spacing: 6) {
				ForEach(1...7, id: \.self) { day in
					let on = WeekdayMask.contains(weekdays, isoDay: day)
					Button {
						weekdays = WeekdayMask.toggling(weekdays, isoDay: day)
					} label: {
						Text(WeekdayMask.shortLabel(isoDay: day))
							.font(.caption.weight(.semibold))
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.background(
								on
									? Color.accentColor
									: Color.secondary.opacity(0.15),
								in: Circle()
							)
							.foregroundStyle(on ? Color.white : Color.primary)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(WeekdayMask.shortLabel(isoDay: day))
					.accessibilityAddTraits(
						on ? .isSelected : []
					)
				}
			}

			Toggle("Only at certain hours", isOn: $restrictHours)

			if restrictHours {
				DatePicker(
					"From",
					selection: DayMinutes.binding($fromMinutes),
					displayedComponents: .hourAndMinute
				)
				DatePicker(
					"To",
					selection: DayMinutes.binding($toMinutes),
					displayedComponents: .hourAndMinute
				)
			}
		} header: {
			Text("When")
		} footer: {
			Text(footer)
		}
	}

	private var footer: LocalizedStringKey {
		if repeats {
			"Fires every time you arrive or leave, on the selected days."
		} else {
			"Fires once, then turns itself off."
		}
	}
}
