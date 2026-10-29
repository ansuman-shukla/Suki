APP_NAME ?= Suki Dev
BUNDLE_ID ?= com.ansumanshukla.suki.dev
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= Suki Dev
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
empty :=
space := $(empty) $(empty)
APP_EXECUTABLE = $(MACOS_DIR)/$(APP_NAME)
APP_EXECUTABLE_TARGET := $(subst $(space),\ ,$(APP_EXECUTABLE))
# Meetings MCP server: a separate stdio tool shipped next to the app executable.
MCP_SOURCES = $(shell find MCP -name '*.swift' -type f | LC_ALL=C sort) \
	Sources/AppName.swift \
	Sources/MeetingStore.swift \
	Sources/MeetingTranscriptCore.swift
MCP_EXECUTABLE = $(MACOS_DIR)/suki-mcp
MCP_EXECUTABLE_TARGET := $(subst $(space),\ ,$(MCP_EXECUTABLE))

SOURCES = $(shell find Sources -name '*.swift' -type f | LC_ALL=C sort)
TEST_RUNNER = $(BUILD_DIR)/SukiTests
TEST_PRODUCTION_SOURCES = \
	MCP/MeetingsMCPServer.swift \
	Sources/APIProvider.swift \
	Sources/AppAppearance.swift \
	Sources/AppContextService.swift \
	Sources/AppName.swift \
	Sources/ContextInferenceFailure.swift \
	Sources/DeepgramTranscriptionService.swift \
	Sources/DictationStats.swift \
	Sources/GeminiLiveTranscriptionService.swift \
	Sources/GeminiTranscriptionService.swift \
	Sources/GlobalShortcutBackend.swift \
	Sources/HomeCopy.swift \
	Sources/HomeHistoryGrouping.swift \
	Sources/LLMAPITransport.swift \
	Sources/LLMCooldownManager.swift \
	Sources/LLMProvider.swift \
	Sources/LiveTranscriptionProvider.swift \
	Sources/MeetingDetectionCore.swift \
	Sources/LiveTranscriptionSession.swift \
	Sources/LiveTypingCore.swift \
	Sources/MeetingAudioCapture.swift \
	Sources/MeetingMicWatchdog.swift \
	Sources/MeetingRecorder.swift \
	Sources/MeetingStore.swift \
	Sources/MeetingTranscriptCore.swift \
	Sources/MeetingTranscriptionPipeline.swift \
	Sources/ModelConfiguration.swift \
	Sources/ModifierKeyEventState.swift \
	Sources/PermissionRepair.swift \
	Sources/PipelineHistoryItem.swift \
	Sources/PostProcessingService.swift \
	Sources/RealtimeTranscriptionService.swift \
	Sources/RecordingCaptureTiming.swift \
	Sources/RecordingTimerPreference.swift \
	Sources/ShortcutBinding.swift \
	Sources/SnippetList.swift \
	Sources/StreamingSTTSession.swift \
	Sources/SukiSound.swift \
	Sources/SyntheticKeystrokeTyper.swift \
	Sources/TranscriptionErrorPresentationCore.swift \
	Sources/TranscriptTextCore.swift \
	Sources/TemperatureCapabilityCache.swift \
	Sources/TranscriptionProvider.swift \
	Sources/TranscriptionService.swift \
	Sources/UpdateManager.swift \
	Sources/UpdateSignatureVerifier.swift \
	Sources/VocabularyList.swift \
	Sources/XAITranscriptionService.swift \
	Sources/WaveformLayout.swift \
	Sources/ShortcutCore/DictationShortcutSessionController.swift \
	Sources/ShortcutCore/ShortcutMatcher.swift \
	Sources/ShortcutCore/ShortcutModels.swift
TEST_SOURCES = $(shell find Tests -name '*.swift' -type f | LC_ALL=C sort)
SHELL_SCRIPTS = $(shell find .github/scripts .agents/skills -name '*.sh' -type f | LC_ALL=C sort)
YAML_FILES = $(shell find .github -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
RESOURCES = $(CONTENTS)/Resources
SOUND_FILES = $(shell find Resources/Sounds -type f -name '*.caf' | LC_ALL=C sort)
ARCH ?= $(shell uname -m)

# Pick the icon source based on which bundle we are building. Dev builds get
# a hammer badge on the icon so a developer's dock shows at a glance
# which Suki they are running when both are installed side by side.
ifeq ($(APP_NAME),Suki Dev)
ICON_SOURCE = Resources/AppIcon-Dev-Source.png
ICON_ICNS = Resources/AppIcon-Dev.icns
else
ICON_SOURCE = Resources/AppIcon-Source.png
ICON_ICNS = Resources/AppIcon.icns
endif

INSTALL_DIR ?= /Applications
INSTALLED_APP = $(INSTALL_DIR)/$(APP_NAME).app

# macOS ties privacy grants (Accessibility, Screen Recording, Microphone) to the
# bundle ID plus its signing certificate. A production-ID build signed by any
# other certificate silently invalidates every user's grants, so only the
# "Suki Release" certificate (SHA-1 below) may sign this bundle ID.
RELEASE_BUNDLE_ID = com.ansumanshukla.suki
RELEASE_CERT_SHA1 = 7003a85059bc0f7b214a0c32a1708de082791f00

.PHONY: all check clean run install icon dmg codesign-dmg notarize test typecheck validate

all: $(APP_EXECUTABLE_TARGET)

# Nested code must be signed before the bundle seals it.
$(MCP_EXECUTABLE_TARGET): $(MCP_SOURCES)
	@mkdir -p "$(MACOS_DIR)"
ifeq ($(ARCH),universal)
	swiftc -o "$(MCP_EXECUTABLE)-arm64" -sdk $(shell xcrun --show-sdk-path) \
		-target arm64-apple-macosx13.0 $(MCP_SOURCES)
	swiftc -o "$(MCP_EXECUTABLE)-x86_64" -sdk $(shell xcrun --show-sdk-path) \
		-target x86_64-apple-macosx13.0 $(MCP_SOURCES)
	lipo -create -output "$(MCP_EXECUTABLE)" "$(MCP_EXECUTABLE)-arm64" "$(MCP_EXECUTABLE)-x86_64"
	@rm "$(MCP_EXECUTABLE)-arm64" "$(MCP_EXECUTABLE)-x86_64"
else
	swiftc -o "$(MCP_EXECUTABLE)" -sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx13.0 $(MCP_SOURCES)
endif
	@codesign --force --options runtime --identifier "$(BUNDLE_ID).mcp" --sign "$(CODESIGN_IDENTITY)" "$(MCP_EXECUTABLE)"

$(APP_EXECUTABLE_TARGET): $(SOURCES) Info.plist $(ICON_ICNS) $(SOUND_FILES) $(MCP_EXECUTABLE_TARGET)
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
ifeq ($(ARCH),universal)
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(APP_NAME)-arm64" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target arm64-apple-macosx13.0 \
		$(SOURCES)
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(APP_NAME)-x86_64" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target x86_64-apple-macosx13.0 \
		$(SOURCES)
	lipo -create -output "$(MACOS_DIR)/$(APP_NAME)" \
		"$(MACOS_DIR)/$(APP_NAME)-arm64" \
		"$(MACOS_DIR)/$(APP_NAME)-x86_64"
	@rm "$(MACOS_DIR)/$(APP_NAME)-arm64" "$(MACOS_DIR)/$(APP_NAME)-x86_64"
else
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx13.0 \
		$(SOURCES)
endif
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleDisplayName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@cp $(ICON_ICNS) "$(RESOURCES)/AppIcon.icns"
	@mkdir -p "$(RESOURCES)/Sounds"
	@cp $(SOUND_FILES) "$(RESOURCES)/Sounds/"
	@plutil -replace NSMicrophoneUsageDescription -string "$(APP_NAME) needs microphone access to transcribe your speech." "$(CONTENTS)/Info.plist"
	@plutil -replace NSSpeechRecognitionUsageDescription -string "$(APP_NAME) needs speech recognition to convert your voice to text." "$(CONTENTS)/Info.plist"
	@plutil -replace NSAccessibilityUsageDescription -string "$(APP_NAME) needs accessibility access to detect the text cursor position and paste transcribed text." "$(CONTENTS)/Info.plist"
	@codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" --entitlements Suki.entitlements "$(APP_BUNDLE)"
	@if [ "$(BUNDLE_ID)" = "$(RELEASE_BUNDLE_ID)" ] && ! codesign -d -r- "$(APP_BUNDLE)" 2>&1 | grep -Eq 'certificate (root|leaf) = H"$(RELEASE_CERT_SHA1)"'; then \
		rm -rf "$(APP_BUNDLE)"; \
		echo "error: $(RELEASE_BUNDLE_ID) must be signed with the Suki Release certificate; other signatures break users' macOS permissions. Build the default Suki Dev bundle instead." >&2; \
		exit 1; \
	fi
	@echo "Built $(APP_BUNDLE)"

check: typecheck test validate

typecheck:
	swiftc \
		-parse-as-library \
		-typecheck \
		-warnings-as-errors \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx13.0 \
		$(SOURCES)
	swiftc \
		-typecheck \
		-warnings-as-errors \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx13.0 \
		$(MCP_SOURCES)

test:
	@mkdir -p "$(BUILD_DIR)"
	swiftc \
		-parse-as-library \
		-warnings-as-errors \
		-o "$(TEST_RUNNER)" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx13.0 \
		$(TEST_PRODUCTION_SOURCES) \
		$(TEST_SOURCES)
	@$(TEST_RUNNER)

validate:
	plutil -lint Info.plist Suki.entitlements
	@set -e; for script in $(SHELL_SCRIPTS); do bash -n "$$script"; done
	@ruby -e 'require "yaml"; ARGV.each { |file| YAML.load_file(file) }' $(YAML_FILES)

icon: $(ICON_ICNS)

$(ICON_ICNS): $(ICON_SOURCE)
	@mkdir -p $(BUILD_DIR)/AppIcon.iconset
	@sips -z 16 16 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16.png > /dev/null
	@sips -z 32 32 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16@2x.png > /dev/null
	@sips -z 32 32 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32.png > /dev/null
	@sips -z 64 64 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32@2x.png > /dev/null
	@sips -z 128 128 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128.png > /dev/null
	@sips -z 256 256 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128@2x.png > /dev/null
	@sips -z 256 256 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256.png > /dev/null
	@sips -z 512 512 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256@2x.png > /dev/null
	@sips -z 512 512 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512.png > /dev/null
	@sips -z 1024 1024 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512@2x.png > /dev/null
	@iconutil -c icns -o $@ $(BUILD_DIR)/AppIcon.iconset
	@rm -rf $(BUILD_DIR)/AppIcon.iconset
	@echo "Generated $@"

dmg: all
	@rm -f "$(BUILD_DIR)/$(APP_NAME).dmg"
	@rm -rf $(BUILD_DIR)/dmg-staging
	@mkdir -p $(BUILD_DIR)/dmg-staging
	@cp -R "$(APP_BUNDLE)" $(BUILD_DIR)/dmg-staging/
	@osascript -e 'tell application "Finder" to make alias file to POSIX file "/Applications" at POSIX file "'"$$(cd $(BUILD_DIR)/dmg-staging && pwd)"'"'
	@ALIAS=$$(find $(BUILD_DIR)/dmg-staging -maxdepth 1 -not -name '*.app' -not -name '.DS_Store' -type f | head -1) && mv "$$ALIAS" "$(BUILD_DIR)/dmg-staging/Applications"
	@fileicon set "$(BUILD_DIR)/dmg-staging/Applications" /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns
	@echo "Creating DMG..."
	@create-dmg \
		--volname "$(APP_NAME)" \
		--volicon "$(ICON_ICNS)" \
		--background "Resources/dmg-background.tiff" \
		--window-pos 200 120 \
		--window-size 660 400 \
		--icon-size 128 \
		--icon "$(APP_NAME).app" 180 170 \
		--hide-extension "$(APP_NAME).app" \
		--icon "Applications" 480 170 \
		--no-internet-enable \
		"$(BUILD_DIR)/$(APP_NAME).dmg" \
		"$(BUILD_DIR)/dmg-staging"
	@rm -rf $(BUILD_DIR)/dmg-staging
	@echo "Created $(BUILD_DIR)/$(APP_NAME).dmg"

codesign-dmg: dmg
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(BUILD_DIR)/$(APP_NAME).dmg"

notarize:
	xcrun notarytool submit "$(BUILD_DIR)/$(APP_NAME).dmg" \
		--keychain-profile "$(NOTARIZE_PROFILE)" --wait
	xcrun stapler staple "$(BUILD_DIR)/$(APP_NAME).dmg"

clean:
	rm -rf $(BUILD_DIR)

run: all
	open "$(APP_BUNDLE)"

# Copy the signed bundle into Applications so it appears in Launchpad and
# Spotlight. Permission grants carry over because they follow the signing
# identity, not the bundle path.
install: all
	@if codesign -dv "$(APP_BUNDLE)" 2>&1 | grep -q 'adhoc'; then \
		echo "error: refusing to install an ad-hoc signed build; macOS drops its permissions on every rebuild. Run 'make clean' and build with a stable identity such as the default Suki Dev." >&2; \
		exit 1; \
	fi
	@osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true
	@while pgrep -xq "$(APP_NAME)"; do sleep 0.2; done
	@rm -rf "$(INSTALLED_APP)"
	@ditto "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	@open "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP)"
