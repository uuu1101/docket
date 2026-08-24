# Docket
#
# Recipes live in Scripts/ so they stay readable: the make that ships with macOS is
# 3.81, which has no .ONESHELL and runs every recipe line in its own shell.

WORKSPACE := Docket.xcworkspace
APP_SCHEME := Docket
KIT_SCHEME := DocketKit
DESTINATION := platform=macOS

.PHONY: help generate build test run release clean

help:
	@echo "generate  regenerate the Xcode project from Project.swift"
	@echo "build     debug build"
	@echo "test      run the DocketKit tests"
	@echo "run       build and launch"
	@echo "release   build, sign and package dist/Docket <version>.dmg"
	@echo "clean     remove build output and dist/"
	@echo ""
	@echo "release honours SIGN_IDENTITY (default: - for ad-hoc), NOTARY_PROFILE"
	@echo "(notarizes and staples the DMG) and CONFIGURATION."

generate:
	tuist generate --no-open

build:
	xcodebuild -workspace $(WORKSPACE) -scheme $(APP_SCHEME) -configuration Debug \
		-destination '$(DESTINATION)' build

test:
	SWIFT_BACKTRACE=interactive=no xcodebuild -workspace $(WORKSPACE) -scheme $(KIT_SCHEME) \
		-configuration Debug -destination '$(DESTINATION)' test

run: build
	@Scripts/run.sh

release:
	@Scripts/release.sh

clean:
	xcodebuild -workspace $(WORKSPACE) -scheme $(APP_SCHEME) clean
	rm -rf dist
