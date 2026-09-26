APP_NAME    := MenubarSpacer
NAME        := menubar-spacer
BUNDLE_ID   := jp.nlink.menubar-spacer
VERSION     := $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.1.0")
BUILD_DIR   := .build/release
DIST_DIR    := dist
APP_BUNDLE  := $(DIST_DIR)/$(APP_NAME).app

# macOS Developer ID signing / notarization (see nlink-jp/.github CONVENTIONS.md
# §Code Signing → GUI apps). Pure SwiftUI/AppKit needs no JIT entitlements —
# Hardened Runtime alone suffices. The app is self-contained (no bundled CLI) and
# requests no TCC permission.
CODESIGN_IDENTITY ?= Developer ID Application
NOTARY_PROFILE    ?= nlink-jp-notary
CODESIGN_SCRIPT := scripts/codesign-darwin-app.sh
NOTARIZE_SCRIPT := scripts/notarize-darwin-app.sh

# App icon: a 1024x1024 source PNG; build-app generates AppIcon.icns into the
# bundle's Resources (sips + iconutil). Missing source → app builds without icon.
ICON_SRC := assets/AppIcon-1024.png

# macOS records the SDK an app was linked against in LC_BUILD_VERSION, and the
# system reads that field to decide which generation of window chrome to draw.
# Since the Xcode 27 / Swift 6.4 toolchain, `swift build` stamps it with the
# deployment target instead of the SDK actually used, so a release built without
# this renders with the previous design — square window corners. Passing
# -platform_version explicitly restores it. MACOS_MIN is read from Package.swift
# so there is one deployment target, not two.
MACOS_MIN := $(shell sed -n -e 's/.*\.macOS(\.v\([0-9][0-9]*\)).*/\1.0/p' \
                            -e 's/.*\.macOS("\([0-9][0-9.]*\)").*/\1/p' Package.swift | head -1)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-version)
SDK_LINK_FLAGS := -Xlinker -platform_version -Xlinker macos -Xlinker $(MACOS_MIN) -Xlinker $(MACOS_SDK)

.PHONY: build build-app package verify-release test clean run

## build: build the release binary
build:
	@mkdir -p $(DIST_DIR)
	@test -n "$(MACOS_MIN)" || { echo "Makefile: no macOS deployment target found in Package.swift"; exit 1; }
	@test -n "$(MACOS_SDK)" || { echo "Makefile: xcrun could not report the macOS SDK version"; exit 1; }
	swift build -c release $(SDK_LINK_FLAGS)

## build-app: assemble the signed .app bundle
build-app: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@sed 's/$${VERSION}/$(VERSION)/g; s/$${BUNDLE_ID}/$(BUNDLE_ID)/g; s/$${APP_NAME}/$(APP_NAME)/g' \
		Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	@if [ -f "$(ICON_SRC)" ]; then \
		scripts/make-icns.sh "$(ICON_SRC)" $(APP_BUNDLE)/Contents/Resources/AppIcon.icns; \
	else \
		echo "[icon] WARN: $(ICON_SRC) not found — building without an app icon"; \
	fi
	@$(CODESIGN_SCRIPT) $(APP_BUNDLE) "$(CODESIGN_IDENTITY)"
	@echo "Built $(APP_BUNDLE) ($(VERSION))"

## package: build-app, notarize + staple the .app, then zip for release
package: build-app
	@$(NOTARIZE_SCRIPT) $(APP_BUNDLE) "$(NOTARY_PROFILE)"
	@cd $(DIST_DIR) && /usr/bin/ditto --norsrc --noextattr -c -k --keepParent $(APP_NAME).app $(NAME)-$(VERSION)-darwin-arm64.zip
	@ls -la $(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip

## verify-release: refuse to release an un-notarized build (marker + staple gate)
verify-release:
	@test -f "$(APP_BUNDLE).notarized" || { \
		echo "verify-release: FAIL — $(APP_BUNDLE) has no notarization marker."; \
		echo "  make package must end with '[notarize-app] ...: Accepted and stapled'. Do not upload."; \
		exit 1; }
	@xcrun stapler validate $(APP_BUNDLE)
	@test -f "$(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip" || { \
		echo "verify-release: FAIL — release zip missing: $(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip"; exit 1; }
	@scripts/verify-app-zip.sh "$(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip"
	@sdk=$$(otool -l "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" | awk '/LC_BUILD_VERSION/{f=1} f && /^ *sdk /{print $$2; exit}'); \
		test "$$sdk" = "$(MACOS_SDK)" || { \
			echo "verify-release: FAIL — linked SDK is $$sdk, expected $(MACOS_SDK)."; \
			echo "  macOS draws an app linked against an old SDK with the previous window chrome."; \
			exit 1; }
	@echo "verify-release: OK ($(VERSION) — marker present, ticket stapled, linked against SDK $(MACOS_SDK))"

## test: run tests
test:
	swift test
	python3 spikes/test_phase1.py
	python3 scripts/check-docs.py

## run: build and run (debug)
run:
	swift run

## clean: remove build artifacts
clean:
	rm -rf $(DIST_DIR) .build

# Homebrew tap generation (see scripts/release-brew.mk). After `make package`,
# `make brew` generates this cask from the built darwin-arm64 zip into the local
# nlink-jp/homebrew-tap checkout.
BREW_KIND := cask
BREW_DESC := Adjust macOS menu bar icon spacing, with exact restore
BREW_NAME := $(NAME)
BREW_APP := $(APP_NAME).app
BREW_BUNDLE_ID := $(BUNDLE_ID)
# macOS 27 is :golden_gate in Homebrew's RELEASES table (26 is :tahoe). The
# template's :big_sur default would advertise support this app does not have.
BREW_MACOS_FLOOR := :golden_gate
include scripts/release-brew.mk
