# GeoRemind
[![Ask DeepWiki](https://devin.ai/assets/askdeepwiki.png)](https://deepwiki.com/drclcomputers/GeoRemind)

<p align="center">
  <img src="assets/img/1.png" width="30%" />
  <img src="assets/img/2.png" width="30%" />
  <img src="assets/img/3.png" width="30%" />
</p>

GeoRemind is a location-based reminder application for iOS. It allows you to set reminders for specific geographic locations and receive a notification the moment you arrive in the area. This app is built entirely with SwiftUI, utilizing MapKit for mapping, CoreLocation for geofencing, and SwiftData for local data persistence.

## Features

-   **Location-Based Reminders:** Create reminders with a title, description, and a customizable radius around a chosen location.
-   **Interactive Map:** View all your active and inactive reminders pinned on an interactive map, visually representing their trigger areas.
-   **Reminder Management:** A comprehensive list to view, edit, delete, and quickly activate or deactivate reminders.
-   **Address Search:** Find and pin locations for your reminders with an integrated address and point-of-interest search.
-   **Smart Geofencing:** To work within the iOS limit of 20 monitored regions, the app intelligently prioritizes and monitors only the closest active reminders to your current location.
-   **Arrival Notifications:** Get notified as soon as you enter a reminder's designated geofence.
-   **Onboarding & Permissions:** A clean onboarding flow for new users and helpful in-app banners to guide the setup of required location and notification permissions.

<p align="center">
  <img src="assets/img/4.png" width="30%" />
  <img src="assets/img/5.png" width="30%" />
  <img src="assets/img/6.png" width="30%" />
</p>

## Core Technologies

-   **UI:** SwiftUI
-   **Data Persistence:** SwiftData
-   **Maps & Location:** MapKit, CoreLocation
-   **Notifications:** UserNotifications

## How It Works

GeoRemind leverages several key iOS frameworks to deliver a seamless experience:

-   **Data Persistence:** All reminders are stored locally using a `ReminderPin` model managed by **SwiftData**.
-   **Geofencing:** The `GeofenceManager` is the heart of the app. It uses `CLLocationManager` to monitor `CLCircularRegion`s. It dynamically updates the set of monitored regions based on the user's significant location changes, ensuring that only the nearest 20 active reminders are tracked to optimize system resources.
-   **Notifications:** The app uses `UNUserNotificationCenter` to request permission and deliver alerts. Arrival notifications are triggered by the `CLLocationManagerDelegate` when the device enters a monitored region.
-   **User Interface:** The entire UI is built with SwiftUI. A `TabView` provides easy navigation between the `MapScreen` and the `Profile` (reminders list). Modals are used for adding and editing reminders.

## Project Structure

The codebase is organized into a standard SwiftUI application structure for clarity and maintainability.

-   `Models/`: Contains the `ReminderPin` SwiftData model.
-   `Views/`: Contains all SwiftUI views, such as `MapScreen`, `Profile` (the reminder list), `Add`, and the `Onboarding` flow.
-   `Services/`: Encapsulates the core logic and interactions with system frameworks.
    -   `GeofenceManagerServ.swift`: Manages all geofencing logic, region monitoring, and location permission status.
    -   `LocationServ.swift`: Provides helper functions for fetching the user's current location.
    -   `NotificationServ.swift`: Handles notification permissions and the creation of notification requests.
    -   `SearchServ.swift`: Powers the location search feature by interfacing with `MKLocalSearchCompleter`.
-   `GeoRemindApp.swift`: The main entry point of the app, which handles the initial view logic (onboarding vs. home) and sets up the SwiftData container.

## How to Run

1.  Clone the repository to your local machine:
    ```bash
    git clone https://github.com/drclcomputers/GeoRemind.git
    ```
2.  Navigate to the project directory and open `GeoRemind.xcodeproj` in Xcode.
3.  Select a target simulator or a physical iOS device.
4.  Build and run the project (Cmd+R).

*Note: For testing geofencing features, using a physical device is highly recommended.*

## Required Permissions

For full functionality, GeoRemind requires the following user permissions:

-   **Location Services:** The app requests "When In Use" permission during onboarding. For reminders to trigger while the app is in the background, users will be prompted to grant "Always" access.
-   **Notifications:** Permission is required to alert you when you arrive at a reminder's location.
