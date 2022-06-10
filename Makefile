BUILD_DIR = $(CURDIR)/build
ARCHIVE_PATH = $(CURDIR)/build/LinearMouse.xcarchive
TARGET_DIR = $(CURDIR)/build/target
TARGET_DMG = $(CURDIR)/build/LinearMouse.dmg

all: configure clean test package

configure: Signing.xcconfig Version.xcconfig

Signing.xcconfig:
	@./scripts/configure-code-signing

Version.xcconfig:
	@./scripts/configure-version

clean:
	rm -fr build

test:
	xcodebuild test -project LinearMouse.xcodeproj -scheme LinearMouse

package: $(TARGET_DMG)

$(BUILD_DIR)/Release/LinearMouse.app:
	xcodebuild archive -project LinearMouse.xcodeproj -scheme LinearMouse -archivePath '$(ARCHIVE_PATH)'
	xcodebuild -exportArchive -archivePath '$(ARCHIVE_PATH)' -exportOptionsPlist ExportOptions.plist -exportPath '$(BUILD_DIR)/Release'

$(TARGET_DMG): $(BUILD_DIR)/Release/LinearMouse.app
	rm -rf '$(TARGET_DIR)'
	rm -f '$(TARGET_DMG)'
	mkdir '$(TARGET_DIR)'
	cp -a '$(BUILD_DIR)/Release/LinearMouse.app' '$(TARGET_DIR)'
	ln -s /Applications '$(TARGET_DIR)/'
	hdiutil create -format UDBZ -srcfolder '$(TARGET_DIR)/' -volname LinearMouse '$(TARGET_DMG)'

prepublish: package
	@./scripts/sign-and-notarize

.PHONY: all configure test build clean package
