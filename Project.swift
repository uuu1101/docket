import ProjectDescription

private let deploymentTargets: DeploymentTargets = .macOS("15.0")

private let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Manual",
    "SWIFT_STRICT_CONCURRENCY": "complete",
]

let project = Project(
    name: "Docket",
    options: .options(automaticSchemesOptions: .enabled()),
    targets: [
        .target(
            name: "DocketKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.taetae.docket.kit",
            deploymentTargets: deploymentTargets,
            sources: ["DocketKit/Sources/**"],
            settings: .settings(base: baseSettings)
        ),
        .target(
            name: "DocketKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.taetae.docket.kit.tests",
            deploymentTargets: deploymentTargets,
            sources: ["DocketKit/Tests/**"],
            dependencies: [.target(name: "DocketKit")],
            settings: .settings(base: baseSettings)
        ),
        .target(
            name: "Docket",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.taetae.docket",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,
                "CFBundleDisplayName": "Docket",
                "CFBundleShortVersionString": "1.0.0",
                "CFBundleVersion": "1",
                "NSHumanReadableCopyright": "",
                // Not a secret: PKCE means no client secret ships with the app.
                // Paste the client ID from api.slack.com here, then run `tuist generate`.
                "SlackClientID": "11863180049027.11863221460355",
                // The https page Slack redirects to; it bounces the browser back to the
                // app's localhost receiver. Required for public distribution — Slack
                // refuses to enable it while any redirect URL is plain http. Leave empty
                // when pairing the build with a personal Slack app that registers the
                // localhost redirects directly.
                "SlackRedirectURL": "https://uuu1101.github.io/docket/slack-callback/",
            ]),
            sources: ["Docket/Sources/**"],
            resources: ["Docket/Resources/**"],
            dependencies: [.target(name: "DocketKit")],
            // PRODUCT_NAME rather than Tuist's productName, which rejects the space.
            settings: .settings(base: baseSettings.merging([
                "PRODUCT_NAME": "Docket",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            ]))
        ),
    ]
)
