SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := debug

BUILD_DIR := $(CURDIR)/.build/xcode
INSTALL_DIR ?= /Applications
BIN_DIR ?= $(HOME)/.local/bin
SIGNING_IDENTITY ?= -
XCODEBUILD ?= xcodebuild
XCODE_FLAGS := -project Switchboard.xcodeproj -scheme Switchboard -destination 'generic/platform=macOS' -derivedDataPath "$(BUILD_DIR)" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="$(SIGNING_IDENTITY)" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp=none" ENABLE_DEBUG_DYLIB=NO
ifeq ($(shell uname -s),Darwin)
SWIFT_FORMAT ?= xcrun swift-format
else
SWIFT_FORMAT ?= swift format
endif
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

.PHONY: verify verify-linux test format format-check debug release debug-install install install-cli clean

verify: format-check test debug release
	python3 scripts/check-bundle.py "$(BUILD_DIR)/Build/Products/Debug/Switchboard.app" "$(BUILD_DIR)/Build/Products/Release/Switchboard.app"
	git diff --check

# Linux subset for cloud sessions: formatting, the Foundation-only tests and whitespace. Not a
# substitute for verify, which also covers the app sources, Xcode builds and bundle checks.
verify-linux: format-check test
	git diff --check

test:
	@mkdir -p .build
	swift test list > .build/test-list.txt
	@test -s .build/test-list.txt || { echo 'No tests were discovered.'; exit 1; }
	swift test --disable-xctest

format:
	$(SWIFT_FORMAT) format --in-place --recursive Switchboard CLI Tests Package.swift

format-check:
	$(SWIFT_FORMAT) lint --strict --recursive Switchboard CLI Tests Package.swift

debug:
	@trap '$(LSREGISTER) -u "$(BUILD_DIR)/Build/Products/Debug/Switchboard.app" >/dev/null 2>&1 || true' EXIT; $(XCODEBUILD) $(XCODE_FLAGS) -configuration Debug build

release:
	@trap '$(LSREGISTER) -u "$(BUILD_DIR)/Build/Products/Release/Switchboard.app" >/dev/null 2>&1 || true' EXIT; $(XCODEBUILD) $(XCODE_FLAGS) -configuration Release build

debug-install: debug
	python3 scripts/install-app.py "$(BUILD_DIR)/Build/Products/Debug/Switchboard.app" "$(INSTALL_DIR)/Switchboard.app"
	$(LSREGISTER) -f "$(INSTALL_DIR)/Switchboard.app"

install: release
	python3 scripts/install-app.py "$(BUILD_DIR)/Build/Products/Release/Switchboard.app" "$(INSTALL_DIR)/Switchboard.app"
	$(LSREGISTER) -f "$(INSTALL_DIR)/Switchboard.app"

# Links the tool inside the installed app, so it is upgraded with the app. Never part of verify.
install-cli:
	@test -x "$(INSTALL_DIR)/Switchboard.app/Contents/Helpers/switchboard" || { echo 'Install the app first with make install.'; exit 1; }
	mkdir -p "$(BIN_DIR)"
	ln -sfn "$(INSTALL_DIR)/Switchboard.app/Contents/Helpers/switchboard" "$(BIN_DIR)/switchboard"

clean:
	rm -rf .build
