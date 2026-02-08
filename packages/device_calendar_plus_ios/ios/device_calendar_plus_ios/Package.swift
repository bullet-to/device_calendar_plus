// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "device_calendar_plus_ios",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "device-calendar-plus-ios", targets: ["device_calendar_plus_ios"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "device_calendar_plus_ios",
            dependencies: [],
            resources: [
                // If your plugin requires a privacy manifest, uncomment the following line.
                // .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
