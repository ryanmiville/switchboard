SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := debug

BUILD_DIR := $(CURDIR)/.build/xcode
INSTALL_DIR ?= /Applications
XCODEBUILD ?= xcodebuild
XCODE_FLAGS := -project Switchboard.xcodeproj -scheme Switchboard -destination 'generic/platform=macOS' -derivedDataPath "$(BUILD_DIR)" CODE_SIGNING_ALLOWED=NO
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

.PHONY: verify test format format-check debug release debug-install install clean

verify: format-check test debug release
	python3 scripts/check-bundle.py "$(BUILD_DIR)/Build/Products/Debug/Switchboard.app" "$(BUILD_DIR)/Build/Products/Release/Switchboard.app"
	git diff --check

test:
	@mkdir -p .build
	swift test list > .build/test-list.txt
	@test -s .build/test-list.txt || { echo 'No tests were discovered.'; exit 1; }
	swift test --disable-xctest

format:
	xcrun swift-format format --in-place --recursive Switchboard Tests Package.swift

format-check:
	xcrun swift-format lint --strict --recursive Switchboard Tests Package.swift

debug:
	@trap '$(LSREGISTER) -u "$(BUILD_DIR)/Build/Products/Debug/Switchboard.app" >/dev/null 2>&1 || true' EXIT; $(XCODEBUILD) $(XCODE_FLAGS) -configuration Debug build

release:
	@trap '$(LSREGISTER) -u "$(BUILD_DIR)/Build/Products/Release/Switchboard.app" >/dev/null 2>&1 || true' EXIT; $(XCODEBUILD) $(XCODE_FLAGS) -configuration Release build

debug-install: debug
	ditto "$(BUILD_DIR)/Build/Products/Debug/Switchboard.app" "$(INSTALL_DIR)/Switchboard.app"
	$(LSREGISTER) -f "$(INSTALL_DIR)/Switchboard.app"

install: release
	ditto "$(BUILD_DIR)/Build/Products/Release/Switchboard.app" "$(INSTALL_DIR)/Switchboard.app"
	$(LSREGISTER) -f "$(INSTALL_DIR)/Switchboard.app"

clean:
	rm -rf .build
