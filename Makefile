.PHONY: all build bundle icon dmg clean install uninstall run generate-secrets

APP_NAME = Nanomuz
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.0.0")
BUILD_DIR = .build/release
BUNDLE = $(APP_NAME).app
DMG = $(APP_NAME)-$(VERSION).dmg
GENERATED_DIR = Sources/Generated

# Last.fm API keys: from environment variables
# For local dev: source .env.local before running make, or set env vars
# On CI: secrets are passed as environment variables

all: bundle

generate-secrets:
	@mkdir -p $(GENERATED_DIR)
	@if [ -f .env.local ]; then set -a; . ./.env.local; set +a; fi; \
	if [ -z "$${LASTFM_API_KEY}" ] || [ -z "$${LASTFM_API_SECRET}" ]; then \
		echo "Error: LASTFM_API_KEY and LASTFM_API_SECRET must be set"; \
		echo "Create .env.local or set environment variables"; \
		exit 1; \
	fi; \
	echo "// Auto-generated file - do not edit" > $(GENERATED_DIR)/Secrets.swift; \
	echo "enum Secrets {" >> $(GENERATED_DIR)/Secrets.swift; \
	echo "    static let lastfmApiKey = \"$${LASTFM_API_KEY}\"" >> $(GENERATED_DIR)/Secrets.swift; \
	echo "    static let lastfmApiSecret = \"$${LASTFM_API_SECRET}\"" >> $(GENERATED_DIR)/Secrets.swift; \
	echo "}" >> $(GENERATED_DIR)/Secrets.swift; \
	echo "Generated Secrets.swift"

build: generate-secrets
	swift build -c release

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
