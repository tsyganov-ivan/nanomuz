.PHONY: all build bundle icon dmg clean install uninstall run inject-keys restore-keys

APP_NAME = Nanomuz
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.0.0")
BUILD_DIR = .build/release
BUNDLE = $(APP_NAME).app
DMG = $(APP_NAME)-$(VERSION).dmg
SOURCE_FILE = Sources/main.swift

# Last.fm API keys: loaded from .env.local (if exists) or environment variables
# Create .env.local with: LASTFM_API_KEY=xxx and LASTFM_API_SECRET=xxx (no quotes!)
ifneq (,$(wildcard .env.local))
    include .env.local
    export
endif

# Strip quotes if present
LASTFM_API_KEY := $(subst ",,$(LASTFM_API_KEY))
LASTFM_API_SECRET := $(subst ",,$(LASTFM_API_SECRET))

LASTFM_API_KEY ?= LASTFM_API_KEY_PLACEHOLDER
LASTFM_API_SECRET ?= LASTFM_API_SECRET_PLACEHOLDER

all: bundle

inject-keys:
	@if [ "$(LASTFM_API_KEY)" != "LASTFM_API_KEY_PLACEHOLDER" ]; then \
		sed -i '' 's/LASTFM_API_KEY_PLACEHOLDER/$(LASTFM_API_KEY)/g' $(SOURCE_FILE); \
		sed -i '' 's/LASTFM_API_SECRET_PLACEHOLDER/$(LASTFM_API_SECRET)/g' $(SOURCE_FILE); \
		echo "Injected Last.fm API keys"; \
	fi

restore-keys:
	@if [ "$(LASTFM_API_KEY)" != "LASTFM_API_KEY_PLACEHOLDER" ]; then \
		sed -i '' 's/$(LASTFM_API_KEY)/LASTFM_API_KEY_PLACEHOLDER/g' $(SOURCE_FILE); \
		sed -i '' 's/$(LASTFM_API_SECRET)/LASTFM_API_SECRET_PLACEHOLDER/g' $(SOURCE_FILE); \
		echo "Restored Last.fm API key placeholders"; \
	fi

build: inject-keys
	swift build -c release
	@$(MAKE) restore-keys

bundle: build
	@mkdir -p $(BUNDLE)/Contents/{MacOS,Resources}
	@cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	@sed 's/1\.0\.0/$(VERSION)/g' Info.plist > $(BUNDLE)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/
	@echo "Created $(BUNDLE) (v$(VERSION))"

dmg: bundle
	@rm -f $(DMG)
	@mkdir -p dmg_temp
	@cp -R $(BUNDLE) dmg_temp/
	@ln -s /Applications dmg_temp/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder dmg_temp -ov -format UDZO $(DMG)
	@rm -rf dmg_temp
	@echo "Created $(DMG)"

install: bundle
	@cp -R $(BUNDLE) /Applications/
	@echo "Installed to /Applications/$(BUNDLE)"

uninstall:
	@rm -rf /Applications/$(BUNDLE)
	@rm -f ~/Library/LaunchAgents/com.nanomuz.plist
	@rm -rf ~/Library/Application\ Support/Nanomuz
	@echo "Uninstalled $(APP_NAME)"

clean:
	swift package clean
	rm -rf $(BUNDLE)
	rm -rf $(DMG)
	rm -rf dmg_temp

run: bundle
	@open $(BUNDLE)

icon:
	@mkdir -p AppIcon.iconset
	swift scripts/generate_icon.swift
	iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
	@rm -rf AppIcon.iconset
	@echo "Icon regenerated"
