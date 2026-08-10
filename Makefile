APP = dist/Battistics.app
DERIVED = .build/xcode
SPARKLE_BIN = $(DERIVED)/SourcePackages/artifacts/sparkle/Sparkle/bin
SIGN_IDENTITY ?= -
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Sources/BattisticsApp/Support/Info.plist)

.PHONY: gen build test app run install icon dmg appcast release clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project Battistics.xcodeproj -scheme Battistics -configuration Debug \
		-derivedDataPath $(DERIVED) build

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

# Regenerates the AppIcon set when rebranding. Drop the master artwork at
# art/icon-art.png first; the generated sizes in the asset catalog are the
# tracked output.
icon:
	@test -f art/icon-art.png || { echo "error: put the master artwork at art/icon-art.png first"; exit 1; }
	swift scripts/make-icon-from-art.swift art/icon-art.png Sources/BattisticsApp/Resources/Assets.xcassets/AppIcon.appiconset

dmg: app
	bash scripts/make-dmg.sh

appcast:
	rm -rf dist/release && mkdir -p dist/release
	cp dist/Battistics-$(VERSION).dmg dist/release/
	$(SPARKLE_BIN)/generate_appcast dist/release \
		--download-url-prefix "https://github.com/doguyilmaz/battistics/releases/download/v$(VERSION)/"

release: appcast
	gh release create v$(VERSION) dist/release/Battistics-$(VERSION).dmg dist/release/appcast.xml \
		--title "Battistics-$(VERSION)" --generate-notes

clean:
	rm -rf .build dist Battistics.xcodeproj
