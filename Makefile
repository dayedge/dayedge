# DayEdge — the usual commands. Each target only names a command; build
# settings live in DayEdge.xcodeproj and the packages.
#
#   make build     the app, via Xcode            → build/DayEdge.app
#                  (signed with "DayEdge Self-Signed" when it exists, else ad hoc;
#                  CONFIGURATION=Debug → build/DayEdge Dev.app, com.dayedge.app.dev,
#                  which runs beside the installed app with its own settings)
#   make signing-identity   create that identity, once (scripts/create-signing-identity.sh)
#   make run       build, then open it
#   make test      all package tests             (Command Line Tools are enough)
#   make release   archive, export and notarize  → build/DayEdge.zip
#   make memory    detailed memory report of the running app (ARGS="--launch", "--stacks", "--track 10:30")
#   make lint      SwiftLint (strict, no baseline) and each target's allowed
#                  imports (scripts/check-modules.sh)
#   make clean
#
# `make build`, `run`, `release` and `lint` need Xcode (SwiftLint uses its
# SourceKit; install it with `brew install swiftlint`); `test` uses Xcode's
# toolchain when it's installed (macOS 26 SDK features on), the Command Line
# Tools otherwise.

PROJECT  := DayEdge.xcodeproj
SCHEME   := DayEdge
APPPKG   := Packages/DayEdge
INDEX    := Packages/CalendarIndex
BUILD    := build
DERIVED  := $(BUILD)/DerivedData

# Xcode's toolchain when it's there; leave DEVELOPER_DIR alone otherwise.
XCODE_DEVELOPER := /Applications/Xcode.app/Contents/Developer
ifneq ($(wildcard $(XCODE_DEVELOPER)),)
export DEVELOPER_DIR ?= $(XCODE_DEVELOPER)
endif

CONFIGURATION ?= Release
# Debug builds are a separate app ("DayEdge Dev", com.dayedge.app.dev).
PRODUCT  := $(if $(filter Debug,$(CONFIGURATION)),DayEdge Dev,DayEdge)
APP      := $(BUILD)/$(PRODUCT).app

# One stable identity keeps macOS's permission grants across builds.
SIGN_IDENTITY := DayEdge Self-Signed
SIGN_KEYCHAIN := $(HOME)/Library/Keychains/dayedge-signing.keychain-db
HAS_SIGN_IDENTITY := $(shell security find-identity -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | grep -c '"$(SIGN_IDENTITY)"')
ifneq ($(HAS_SIGN_IDENTITY),0)
SIGNING := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" DEVELOPMENT_TEAM= \
	OTHER_CODE_SIGN_FLAGS="--keychain $(SIGN_KEYCHAIN) --timestamp=none"
endif

.PHONY: build run test release memory lint clean signing-identity

build:
ifeq ($(HAS_SIGN_IDENTITY),0)
	@echo "Signing ad hoc: macOS will ask for permissions again after each build (make signing-identity)."
else
	@security unlock-keychain -p dayedge-signing "$(SIGN_KEYCHAIN)"
endif
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED) $(SIGNING) build
	rm -rf "$(APP)"
	cp -R "$(DERIVED)/Build/Products/$(CONFIGURATION)/$(PRODUCT).app" "$(APP)"
	@echo "Built $(APP)"

run: build
	-pkill -x "$(PRODUCT)"
	open "$(APP)"

test:
	swift test --package-path $(APPPKG)
	swift test --package-path $(INDEX)

# Developer ID distribution. Needs, once:
#   TEAM=<your Apple team ID>
#   xcrun notarytool store-credentials <NOTARY_PROFILE> …  (an app-specific password or API key)
#   make release TEAM=ABCDE12345 NOTARY_PROFILE=dayedge
release:
	@test -n "$(TEAM)" || (echo "Set TEAM=<your Apple team ID>"; exit 1)
	@test -n "$(NOTARY_PROFILE)" || (echo "Set NOTARY_PROFILE=<notarytool keychain profile>"; exit 1)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) -archivePath $(BUILD)/DayEdge.xcarchive \
		DEVELOPMENT_TEAM=$(TEAM) archive
	/usr/libexec/PlistBuddy -c "Clear dict" \
		-c "Add :method string developer-id" -c "Add :teamID string $(TEAM)" \
		-c "Add :signingStyle string automatic" $(BUILD)/ExportOptions.plist
	xcodebuild -exportArchive -archivePath $(BUILD)/DayEdge.xcarchive \
		-exportOptionsPlist $(BUILD)/ExportOptions.plist -exportPath $(BUILD)/export
	ditto -c -k --keepParent $(BUILD)/export/DayEdge.app $(BUILD)/DayEdge-notarize.zip
	xcrun notarytool submit $(BUILD)/DayEdge-notarize.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(BUILD)/export/DayEdge.app
	ditto -c -k --keepParent $(BUILD)/export/DayEdge.app $(BUILD)/DayEdge.zip
	@echo "Notarized $(BUILD)/DayEdge.zip"

signing-identity:
	scripts/create-signing-identity.sh "$(SIGN_IDENTITY)" "$(SIGN_KEYCHAIN)"

memory:
	scripts/memory-report.sh $(ARGS)

SWIFTLINT := $(shell command -v swiftlint 2>/dev/null)

lint:
	@test -n "$(SWIFTLINT)" || (echo "SwiftLint isn't installed: brew install swiftlint"; exit 1)
	swiftlint lint --quiet --strict
	scripts/check-modules.sh
	python3 scripts/check-localizations.py

clean:
	rm -rf $(BUILD) $(APPPKG)/.build $(INDEX)/.build
