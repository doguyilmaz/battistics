APP = dist/Battistics.app
DERIVED = .build/xcode
SPARKLE_BIN = $(DERIVED)/SourcePackages/artifacts/sparkle/Sparkle/bin
SIGN_IDENTITY ?= -
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' App/Support/Info.plist)

.PHONY: gen build test app run install icon dmg appcast release clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project Battistics.xcodeproj -scheme Battistics -configuration Debug \
		-derivedDataPath $(DERIVED) build

test:
	cd BattisticsCore && swift test

app: gen
	xcodebuild -project Battistics.xcodeproj -scheme Battistics -configuration Release \
		-derivedDataPath $(DERIVED) build \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" $(if $(filter -,$(SIGN_IDENTITY)),,CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
	rm -rf dist && mkdir -p dist
	ditto $(DERIVED)/Build/Products/Release/Battistics.app $(APP)

run: build
	open $(DERIVED)/Build/Products/Debug/Battistics.app

install: app
	rm -rf /Applications/Battistics.app
	ditto $(APP) /Applications/Battistics.app
	@echo "Installed to /Applications/Battistics.app"

# Prefers real artwork at art/icon-art.png, falls back to the code-drawn mark.
icon:
	@if [ -f art/icon-art.png ]; then \
		swift scripts/make-icon-from-art.swift art/icon-art.png App/Resources/Assets.xcassets/AppIcon.appiconset; \
	else \
		swift scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset; \
	fi

dmg: app
	bash scripts/make-dmg.sh

appcast:
	rm -rf dist/release && mkdir -p dist/release
	cp dist/Battistics-$(VERSION).dmg dist/release/
	$(SPARKLE_BIN)/generate_appcast dist/release \
		--download-url-prefix "https://github.com/doguyilmaz/battistics/releases/download/v$(VERSION)/"

release: appcast
	gh release create v$(VERSION) dist/release/Battistics-$(VERSION).dmg dist/release/appcast.xml \
		--title "Battistics $(VERSION)" --generate-notes

clean:
	rm -rf .build dist Battistics.xcodeproj
