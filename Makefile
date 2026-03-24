APP_NAME := TmuxVTab
BUNDLE_ID := app.tru2dagame.tmuxvtab
BUILD_DIR := .build/release
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: build run bundle install clean link

build:
	swift build -c release

run:
	swift build && .build/debug/$(APP_NAME)

bundle: build
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	@/usr/libexec/PlistBuddy -c "Clear dict" "$(APP_BUNDLE)/Contents/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy \
		-c "Add :CFBundleExecutable string $(APP_NAME)" \
		-c "Add :CFBundleIdentifier string $(BUNDLE_ID)" \
		-c "Add :CFBundleName string $(APP_NAME)" \
		-c "Add :CFBundleVersion string 1.0" \
		-c "Add :CFBundleShortVersionString string 1.0" \
		-c "Add :LSUIElement bool true" \
		-c "Add :LSMinimumSystemVersion string 15.0" \
		"$(APP_BUNDLE)/Contents/Info.plist"
	@echo "Built $(APP_BUNDLE)"

install: bundle
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

link:
	@ln -sf "$(CURDIR)/bin/tmuxvtab" /usr/local/bin/tmuxvtab
	@echo "Linked tmuxvtab → /usr/local/bin/tmuxvtab"

clean:
	swift package clean
