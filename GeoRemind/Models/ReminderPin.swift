//
//  ReminderPin.swift
//  GeoRemind
//
//  Created by Dorneanu Denis on 14/09/2026.
//

import SwiftData
import Foundation
import CoreLocation

@Model
class ReminderPin {
    var id: UUID = UUID()
    var title: String
    var desc: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var isActive: Bool
    var timestamp: Date
    
    init(title: String, desc: String, latitude: Double, longitude: Double, radius: Double, isActive: Bool = true, timestamp: Date = .now) {
        self.title = title
        self.desc = desc
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isActive = isActive
        self.timestamp = timestamp
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
