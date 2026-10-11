# Contributing Guide

Thank you for investing your time in contributing to LinearMouse!

Read our [Code of Conduct](CODE_OF_CONDUCT.md) to keep our community approachable and respectable.

## Build Instructions

Instructions for building LinearMouse on macOS.

### Dependencies

- [Xcode](https://apps.apple.com/app/xcode/id497799835), with a Swift 6.0 or newer toolchain
- [SwiftLint](https://github.com/realm/SwiftLint), used to lint Swift files
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), used to format Swift files
- `npm` & [ts-json-schema-generator](https://www.npmjs.com/package/ts-json-schema-generator), used to generate the configuration JSON schema

Install tools using brew:

```bash
$ brew install npm swiftlint swiftformat
```

### Set up the repository

```sh
$ git clone https://github.com/linearmouse/linearmouse.git
$ cd linearmouse
$ npm install
```

### Configure code signing

Code signing is required by Apple. You can generate a code signing configuration by running

```
$ make configure
```

> Note: If you want to contribute to LinearMouse, please don't modify the ‘Signing & Capabilities’ configurations directly in Xcode. Instead, use `make configure` or modify the `Signing.xcconfig`.

If there are no available code signing certificates in your Keychain, it will generate a configuration that uses ad-hoc certificates to sign the app.

When using ad-hoc signing, you may need to grant accessibility permission again after rebuilding the app.
In that case, using Apple Development certificates is recommended.
You can create an Apple Development certificate [in Xcode](https://help.apple.com/xcode/mac/current/#/dev154b28f09), which is totally free.

### Build

Now, you can build and package LinearMouse by running

```sh
$ make
```
