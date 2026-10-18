// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RayNeoSteady",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "RayNeoSteady", targets: ["RayNeoSteady"])],
    targets: [
        .target(name: "CRayNeo", exclude: ["LICENSE"], publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "SteadyCore"),
        .executableTarget(name: "RayNeoSteady", dependencies: ["CRayNeo", "SteadyCore"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("MetalKit"),
                                           .linkedFramework("ScreenCaptureKit"), .linkedFramework("Carbon")]),
        .testTarget(name: "SteadyCoreTests", dependencies: ["SteadyCore"])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
