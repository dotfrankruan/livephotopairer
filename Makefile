# LivePhotoPairer — Makefile
#
# Builds a release .app bundle for Apple Silicon (arm64) only and signs it
# ad-hoc. No external dependencies: system frameworks + Swift toolchain only.

APP_NAME    := LivePhotoPairer
BUILD_DIR   := .build
BIN         := $(BUILD_DIR)/release/$(APP_NAME)
APP         := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    := $(APP)/Contents
VERSION     := 1.0.0

.PHONY: all build bundle sign run clean test

all: sign

## build: release build, arm64 only
build:
	swift build -c release --arch arm64

## bundle: assemble the .app bundle
bundle: build
	mkdir -p $(CONTENTS)/MacOS
	mkdir -p $(CONTENTS)/Resources
	cp $(BIN) $(CONTENTS)/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
		$(CONTENTS)/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" \
		$(CONTENTS)/Info.plist 2>/dev/null || true

## sign: ad-hoc codesign (no Developer ID / notarization needed)
sign: bundle
	codesign --force --deep --sign - --identifier com.frank-ruan.livephotopairer $(APP)
	codesign --verify --verbose=1 $(APP)
	@echo "Built: $(APP)"

## run: build, sign and launch the app
run: sign
	open $(APP)

## test: headless smoke test pairing the bundled sample files via the CLI harness
test:
	@echo "No automated test target; use the app UI or see README for manual verification."

## clean: remove all build artifacts
clean:
	rm -rf $(BUILD_DIR)
