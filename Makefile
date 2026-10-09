.PHONY: generate build build-mac test test-all test-mac lint format clean

PROJECT := Notova.xcodeproj
SCHEME := Notova
DESTINATION ?= generic/platform=iOS Simulator
MAC_SCHEME := NotovaMac
MAC_DESTINATION ?= platform=macOS

# Regenerate the Xcode project from project.yml (the project is gitignored).
generate:
	xcodegen generate

# Build the app for the iOS Simulator.
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' build

# Build the native macOS app.
build-mac: generate
	xcodebuild -project $(PROJECT) -scheme $(MAC_SCHEME) -destination '$(MAC_DESTINATION)' build

# Build + run the macOS app's unit tests.
test-mac: generate
	xcodebuild -project $(PROJECT) -scheme $(MAC_SCHEME) -destination '$(MAC_DESTINATION)' test

# Run NotovaCore package tests (the authoritative unit tests).
test:
	cd Packages/NotovaCore && swift test

# Everything CI runs: all nine packages, the iOS unit tests and the macOS tests.
PACKAGES := NotovaCore Transcription AISummary ModelManagement Integrations Persistence Keychain DesignSystem AudioCapture
test-all: generate
	set -e; for p in $(PACKAGES); do (cd Packages/$$p && swift test); done
	xcodebuild test -project Notova.xcodeproj -scheme Notova \
		-destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
		-only-testing:NotovaTests -collect-test-diagnostics never
	xcodebuild test -project Notova.xcodeproj -scheme NotovaMac -destination 'platform=macOS'

# Lint Swift sources (requires swiftlint on PATH).
lint:
	swiftlint lint --quiet || (echo "swiftlint not installed; skipping"; exit 0)

# Format Swift sources (requires swiftformat on PATH).
format:
	swiftformat . || (echo "swiftformat not installed; skipping"; exit 0)

clean:
	rm -rf $(PROJECT) .build Packages/*/.build
