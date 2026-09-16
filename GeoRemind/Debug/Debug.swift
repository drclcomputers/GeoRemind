//
//  Debug.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import SwiftUI

struct FontListPreview: View {
    let families = UIFont.familyNames.sorted()

    var body: some View {
        NavigationStack {
            List {
                ForEach(families, id: \.self) { family in
                    Section(header: Text(family).font(.headline)) {
                        ForEach(UIFont.fontNames(forFamilyName: family), id: \.self) { fontName in
                            HStack {
                                Text(fontName)
                                    .font(.custom(fontName, size: 16))
                                Spacer()
                                Text(fontName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("System Fonts")
        }
    }
}
