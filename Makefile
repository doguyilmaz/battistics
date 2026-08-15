APP = dist/Battistics.app
DERIVED = .build/xcode
SPARKLE_BIN = $(DERIVED)/SourcePackages/artifacts/sparkle/Sparkle/bin
SIGN_IDENTITY ?= -
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Sources/BattisticsApp/Support/Info.plist)

.PHONY: gen build test app run install dmg appcast release clean

gen:
	xcodegen generate

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

install: app
	rm -rf /Applications/Battistics.app
	ditto $(APP) /Applications/Battistics.app
	@echo "Installed to /Applications/Battistics.app"

dmg: app
	bash scripts/make-dmg.sh

appcast:
	rm -rf dist/release && mkdir -p dist/release
	cp dist/Battistics-$(VERSION).dmg dist/release/
	$(SPARKLE_BIN)/generate_appcast dist/release \
		--download-url-prefix "https://github.com/doguyilmaz/battistics/releases/download/v$(VERSION)/"
	mv dist/release/appcast.xml dist/release/appcast-2.xml
	cp scripts/legacy-appcast.xml dist/release/appcast.xml

release: appcast
	awk -v want="## $(VERSION)" '$$0 == want { f = 1; next } /^## / { if (f) exit } f' \
		CHANGELOG.md > dist/release/notes.md
	gh release create v$(VERSION) dist/release/Battistics-$(VERSION).dmg \
		dist/release/appcast-2.xml dist/release/appcast.xml \
		--title "Battistics-$(VERSION)" --notes-file dist/release/notes.md

clean:
	rm -rf .build dist Battistics.xcodeproj
