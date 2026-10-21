APP = dist/Battistics.app
DERIVED = .build/xcode
SIGN_IDENTITY ?= -

.PHONY: gen build test app run install metrics clean

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

metrics:
	@./scripts/metrics.sh

clean:
	rm -rf .build dist Battistics.xcodeproj
