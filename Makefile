# pressf4 — build a sandboxed macOS .app with swiftc (no Xcode project).
#
# Usage:
#   make           # build the .app
#   make run       # build + launch
#   make clean
#   make open      # reveal in Finder
#   make install   # copy to /Applications

APP_NAME      := pressf4
BUNDLE_ID     := com.rafaelje.pressf4
MIN_MACOS     := 14.0
ARCH          := $(shell uname -m)
TARGET        := $(ARCH)-apple-macos$(MIN_MACOS)

# Prefer a stable signing identity (Apple Development cert) so TCC permissions
# (Screen Recording, etc.) survive across rebuilds. Falls back to ad-hoc.
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning -v 2>/dev/null | awk '/Apple Development/ {print $$2; exit}')
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := -
SIGN_LABEL    := ad-hoc (permissions reset every rebuild)
else
SIGN_LABEL    := Apple Development ($(SIGN_IDENTITY))
endif

BUILD_DIR     := build
APP_BUNDLE    := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS      := $(APP_BUNDLE)/Contents
MACOS_DIR     := $(CONTENTS)/MacOS
RES_DIR       := $(CONTENTS)/Resources
EXECUTABLE    := $(MACOS_DIR)/$(APP_NAME)

SOURCES       := $(shell find Sources -name '*.swift')
INFO_PLIST    := Resources/Info.plist
ENTITLEMENTS  := Resources/CapturaApp.entitlements
APP_ICON      := Resources/AppIcon.icns

CACHE_DIR     := $(abspath $(BUILD_DIR)/cache)
MODULE_CACHE  := $(CACHE_DIR)/modules

SWIFT_FLAGS   := -O \
                 -target $(TARGET) \
                 -parse-as-library \
                 -module-cache-path $(MODULE_CACHE) \
                 -Xcc -fmodules-cache-path=$(MODULE_CACHE) \
                 -framework AppKit \
                 -framework SwiftUI \
                 -framework ScreenCaptureKit \
                 -framework Carbon \
                 -framework UniformTypeIdentifiers \
                 -framework CoreGraphics \
                 -framework UserNotifications

# Force xcrun / clang to use the writable build cache dir.
export TMPDIR := $(CACHE_DIR)/tmp
export CLANG_MODULE_CACHE_PATH := $(MODULE_CACHE)
export SWIFT_MODULE_CACHE_PATH := $(MODULE_CACHE)

.PHONY: all build run clean open install resign test icon

ICON_SVG      := images/icon.svg
ICONSET_DIR   := images/AppIcon.iconset

all: build

test:
	@env -u TMPDIR -u CLANG_MODULE_CACHE_PATH -u SWIFT_MODULE_CACHE_PATH swift test

build: $(EXECUTABLE) $(CONTENTS)/Info.plist $(RES_DIR)/AppIcon.icns sign

$(EXECUTABLE): $(SOURCES) | $(MACOS_DIR) $(CACHE_DIR)
	@echo "→ Compiling $(APP_NAME) for $(TARGET)…"
	@xcrun swiftc $(SWIFT_FLAGS) -o $@ $(SOURCES)
	@echo "✓ Built $@"

$(MACOS_DIR):
	@mkdir -p $(MACOS_DIR) $(RES_DIR)

$(CACHE_DIR):
	@mkdir -p $(MODULE_CACHE) $(TMPDIR)

$(CONTENTS)/Info.plist: $(INFO_PLIST) | $(MACOS_DIR)
	@cp $(INFO_PLIST) $@
	@echo "✓ Info.plist copied"

$(RES_DIR)/AppIcon.icns: $(APP_ICON) | $(MACOS_DIR)
	@cp $(APP_ICON) $@
	@echo "✓ AppIcon.icns copied"

sign: $(EXECUTABLE) $(ENTITLEMENTS)
	@echo "→ Signing with $(SIGN_LABEL)…"
	@codesign --force --deep --sign $(SIGN_IDENTITY) \
	          --entitlements $(ENTITLEMENTS) \
	          --options runtime \
	          $(APP_BUNDLE)
	@echo "✓ Signed"
	@codesign -dv --entitlements - $(APP_BUNDLE) 2>&1 | head -20

run: build
	@echo "→ Launching $(APP_NAME)…"
	@open $(APP_BUNDLE)

clean:
	@rm -rf $(BUILD_DIR)
	@echo "✓ Clean"

open:
	@open -R $(APP_BUNDLE)

install: build
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "✓ Installed to /Applications/$(APP_NAME).app"

resign: $(ENTITLEMENTS)
	@codesign --force --deep --sign $(SIGN_IDENTITY) \
	          --entitlements $(ENTITLEMENTS) \
	          --options runtime \
	          $(APP_BUNDLE)

# Regenerate AppIcon.icns from images/icon.svg. Requires rsvg-convert (brew install librsvg).
icon: $(ICON_SVG)
	@command -v rsvg-convert >/dev/null 2>&1 || { echo "✗ rsvg-convert not found — run: brew install librsvg"; exit 1; }
	@echo "→ Rendering iconset from $(ICON_SVG)…"
	@mkdir -p $(ICONSET_DIR)
	@for s in 16 32 64 128 256 512 1024; do \
	    rsvg-convert -w $$s -h $$s $(ICON_SVG) -o $(ICONSET_DIR)/_$$s.png; \
	done
	@mv $(ICONSET_DIR)/_16.png   $(ICONSET_DIR)/icon_16x16.png
	@cp $(ICONSET_DIR)/_32.png   $(ICONSET_DIR)/icon_16x16@2x.png
	@mv $(ICONSET_DIR)/_32.png   $(ICONSET_DIR)/icon_32x32.png
	@cp $(ICONSET_DIR)/_64.png   $(ICONSET_DIR)/icon_32x32@2x.png
	@rm  $(ICONSET_DIR)/_64.png
	@mv $(ICONSET_DIR)/_128.png  $(ICONSET_DIR)/icon_128x128.png
	@cp $(ICONSET_DIR)/_256.png  $(ICONSET_DIR)/icon_128x128@2x.png
	@mv $(ICONSET_DIR)/_256.png  $(ICONSET_DIR)/icon_256x256.png
	@cp $(ICONSET_DIR)/_512.png  $(ICONSET_DIR)/icon_256x256@2x.png
	@mv $(ICONSET_DIR)/_512.png  $(ICONSET_DIR)/icon_512x512.png
	@mv $(ICONSET_DIR)/_1024.png $(ICONSET_DIR)/icon_512x512@2x.png
	@iconutil --convert icns $(ICONSET_DIR) --output $(APP_ICON)
	@echo "✓ Wrote $(APP_ICON) and refreshed $(ICONSET_DIR)/"
