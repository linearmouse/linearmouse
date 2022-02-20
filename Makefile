BUILD_DIR = $(CURDIR)/build
TARGET_DIR = $(CURDIR)/build/target
TARGET_DMG = $(CURDIR)/build/LinearMouse.dmg

all: configure clean test package

configure: Signing.xcconfig Version.xcconfig

Signing.xcconfig:
	@./scripts/configure-code-signing

Version.xcconfig:
	@./scripts/configure-version

test:
	xcodebuild test -project LinearMouse.xcodeproj -scheme LinearMouse

build:
	xcodebuild -configuration Release -target LinearMouse SYMROOT='$(BUILD_DIR)'

clean:
	rm -fr build

package: build
	rm -f '$(TARGET_DIR)'
	rm -f '$(TARGET_DMG)'
	mkdir '$(TARGET_DIR)'
	cp -a '$(BUILD_DIR)/Release/LinearMouse.app' '$(TARGET_DIR)'
	ln -s /Applications '$(TARGET_DIR)/'
	hdiutil create -fs HFS+ -srcfolder '$(TARGET_DIR)/' -volname LinearMouse '$(TARGET_DMG)'

.PHONY: all configure test build clean package
