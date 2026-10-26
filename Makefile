APP = dist/Battistics.app
DERIVED = .build/xcode
SIGN_IDENTITY ?= -

.PHONY: gen build test app run run-icloud install dmg tap metrics clean

# The app resolves the same package versions as `swift test`; only Sparkle,
# pinned exactly in project.yml, is added on top.
gen:
	xcodegen generate
	mkdir -p Battistics.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
	cp Package.resolved Battistics.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# SIGN_IDENTITY defaults to ad-hoc, which is fine until you need the
# privileged helper: SMAppService will not register a daemon without a real
# team identifier. Build with
#   SIGN_IDENTITY="Developer ID Application: ..." make run
# to exercise that path locally.
build: gen
	xcodebuild -project Battistics.xcodeproj -scheme Battistics -configuration Debug \
		-derivedDataPath $(DERIVED) build \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" $(if $(filter -,$(SIGN_IDENTITY)),,CODE_SIGN_STYLE=Manual CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")

test:
	swift test

app: gen
	xcodebuild -project Battistics.xcodeproj -scheme Battistics -configuration Release \
		-derivedDataPath $(DERIVED) build \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" $(if $(filter -,$(SIGN_IDENTITY)),,CODE_SIGN_STYLE=Manual CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
	rm -rf dist && mkdir -p dist
	ditto $(DERIVED)/Build/Products/Release/Battistics.app $(APP)
	SIGN_IDENTITY="$(SIGN_IDENTITY)" bash scripts/sign-app.sh $(APP)

run: build
	open $(DERIVED)/Build/Products/Debug/Battistics.app

# Debug build signed for iCloud, for the iPhone companion. Xcode creates the
# development profile; quit any other copy of Battistics first. When the host
# already has a Developer ID registration for the root helper in BTM, launchd's
# launch constraint expects that certificate category on the helper binary.
TEAM ?= 5MYT4VYJFC
HELPER_SIGN_IDENTITY ?= Developer ID Application
run-icloud: gen
	xcodebuild -project Battistics.xcodeproj -scheme Battistics -configuration Debug \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates build \
		DEVELOPMENT_TEAM=$(TEAM) CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
		BATTISTICS_ENTITLEMENTS=Sources/BattisticsApp/Support/Battistics.entitlements
	@if security find-identity -v -p codesigning | grep -q "$(HELPER_SIGN_IDENTITY)"; then \
		codesign -f -s "$(HELPER_SIGN_IDENTITY)" -o runtime --timestamp \
			$(DERIVED)/Build/Products/Debug/Battistics.app/Contents/MacOS/BattisticsPowerHelper; \
	fi
	open $(DERIVED)/Build/Products/Debug/Battistics.app

install: app
	rm -rf /Applications/Battistics.app
	ditto $(APP) /Applications/Battistics.app
	@echo "Installed to /Applications/Battistics.app"

dmg: app
	bash scripts/make-dmg.sh

# Only needed if the release job's cask step was skipped or failed.
# The working tree's version is a placeholder, so ask GitHub what shipped.
# Override with `make tap V=1.2.0`.
tap:
	@./scripts/update-tap.sh $(if $(V),$(V),$(shell gh release view --json tagName --jq '.tagName' | sed 's/^v//'))

metrics:
	@./scripts/metrics.sh

clean:
	rm -rf .build dist Battistics.xcodeproj
