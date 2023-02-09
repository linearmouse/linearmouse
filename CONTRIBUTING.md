# Contributing guide

Thank you for investing your time in contributing to LinearMouse!

Read our [Code of Conduct](CODE_OF_CONDUCT.md) to keep our community approachable and respectable.

## Build instructions

Instructions for building LinearMouse on macOS.

### Setup the repository

```sh
$ git clone https://github.com/linearmouse/linearmouse.git
$ cd linearmouse
```

### Configure code signing

Code signing is required by Apple. You can generate a code signing configuration by running

```
$ make configure
```

> Note: If you want to contribute to LinearMouse, please don't modify the ‘Signing & Capabilities’ configurations directly in Xcode. Instead, use `make configure` or modify the `Signing.xcconfig`.

If there are no available code signing certificates in your Keychain, it will generate a configuration that uses ad-hoc certificates to sign the app.

By using ad-hoc certificates, you'll have to [grant accessibility permissions](https://github.com/linearmouse/linearmouse#accessibility-permission) for each builds.
In that case, using Apple Development certificates is recommended.
You can create an Apple Development certificate [in Xcode](https://help.apple.com/xcode/mac/current/#/dev154b28f09), which is totally free.

### Build

Now, you can build and package LinearMouse by running

```sh
$ make
```
