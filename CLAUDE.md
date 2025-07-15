# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LinearMouse is a macOS utility app that enhances mouse and trackpad functionality. It's built with Swift and uses SwiftUI for the user interface. The app provides customizable mouse button mappings, scrolling behavior, and pointer settings that can be configured per-device, per-application, or per-display.

## Development Commands

### Build and Test
```bash
# Build the project
xcodebuild -project LinearMouse.xcodeproj -scheme LinearMouse

# Run tests
make test
# or
xcodebuild test -project LinearMouse.xcodeproj -scheme LinearMouse

# Full build pipeline (configure, clean, lint, test, package)
make all
```

### Code Quality
```bash
# Lint the codebase
make lint
# or run individually:
swiftformat --lint .
swiftlint .

# Clean build artifacts
make clean
```

### Packaging
```bash
# Create DMG package
make package

# For release (requires signing certificates)
make configure-release
make prepublish
```

### Configuration Schema Generation
```bash
# Generate JSON schema from TypeScript definitions
npm run generate:json-schema
```

## Architecture Overview

### Core Components

1. **EventTransformer System** (`LinearMouse/EventTransformer/`):
   - `EventTransformerManager`: Central coordinator that manages event processing
   - Individual transformers handle specific functionality (scrolling, button mapping, etc.)
   - Uses LRU cache for performance optimization

2. **Configuration System** (`LinearMouse/Model/Configuration/`):
   - `Configuration.swift`: Main configuration model with JSON schema validation
   - `Scheme.swift`: Defines device-specific settings
   - `DeviceMatcher.swift`: Logic for matching devices to configurations

3. **Device Management** (`LinearMouse/Device/`):
   - `DeviceManager.swift`: Manages connected input devices
   - `Device.swift`: Represents individual input devices

4. **Event Processing** (`LinearMouse/EventTap/`):
   - `GlobalEventTap.swift`: Captures system-wide input events
   - `EventTap.swift`: Base event handling functionality

5. **User Interface** (`LinearMouse/UI/`):
   - SwiftUI-based settings interface
   - Modular components for different settings categories
   - State management using `@Published` properties

### Custom Modules

The project includes several custom Swift packages in the `Modules/` directory:

- **KeyKit**: Keyboard input handling and simulation
- **PointerKit**: Mouse/trackpad device interaction
- **GestureKit**: Gesture recognition (zoom, navigation swipes)
- **DockKit**: Dock integration utilities
- **ObservationToken**: Observation pattern utilities

### Key Patterns

1. **Event Transformation Pipeline**: Events flow through multiple transformers in sequence
2. **Configuration-Driven Behavior**: All functionality is controlled by JSON configuration
3. **Device Matching**: Settings are applied based on device type, application, or display
4. **State Management**: Uses Combine framework for reactive state updates

## Important Development Notes

- The app requires accessibility permissions to function
- Event processing happens at the system level using CGEvent
- Configuration is stored as JSON and validated against a schema
- The project uses Swift Package Manager for dependencies
- Localization is handled through Crowdin integration
- Code signing is required for distribution (see `Scripts/` directory)

## Testing

- Unit tests are in `LinearMouseUnitTests/`
- Focus on testing event transformers and configuration parsing
- Run tests before submitting changes: `make test`

## Configuration Structure

The app uses a JSON configuration format with:
- `schemes`: Array of device-specific configurations
- Each scheme can target specific devices, applications, or displays
- Settings include button mappings, scrolling behavior, and pointer adjustments
- Configuration schema is defined in `Documentation/Configuration.d.ts`