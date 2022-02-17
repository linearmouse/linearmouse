<h1 align="center">
  <a href="https://linearmouse.org/">
    <img src="logo.svg" width="128" height="128" />
    <br />
    LinearMouse
  </a>
</h1>

<p align="center">
  <a href="https://github.com/linearmouse/linearmouse/releases/latest"><img alt="GitHub release (latest SemVer)" src="https://img.shields.io/github/v/release/linearmouse/linearmouse?sort=semver"></a>
  <a href="https://github.com/linearmouse/linearmouse/releases/latest/download/LinearMouse.dmg"><img src="https://img.shields.io/github/downloads/linearmouse/linearmouse/total" alt="Downloads" /></a>
  <img src="https://img.shields.io/github/license/linearmouse/linearmouse" alt="MIT License" />
  <a href="https://crowdin.com/project/linearmouse"><img src="https://badges.crowdin.net/linearmouse/localized.svg" alt="Crowdin" /></a>
</p>

LinearMouse is a free and open-source utility for macOS which aims to
improve the experience and functionality of third-party mice.

## Screenshots

<table>
  <tbody>
      <td width="33%">
        <img width="100%" alt="General" src="https://user-images.githubusercontent.com/3000535/153178582-1f3ec383-39be-4afb-aa26-84bb5e4d837c.png#gh-light-mode-only">
        <img width="100%" alt="General" src="https://user-images.githubusercontent.com/3000535/153179006-600e65cf-8c94-497e-959b-48817cf02420.png#gh-dark-mode-only">
      </td>
      <td width="33%">
        <img width="100%" alt="Cursor" src="https://user-images.githubusercontent.com/3000535/153178851-bf06f44f-4e01-4d7b-848d-3e2eb3d46f9f.png#gh-light-mode-only">
        <img width="100%" alt="Cursor" src="https://user-images.githubusercontent.com/3000535/153179057-c24d8cf0-4ab2-42f2-9a5e-867cc4a8bf57.png#gh-dark-mode-only">
      </td>
      <td width="33%">
        <img width="100%" alt="Modifier keys" src="https://user-images.githubusercontent.com/3000535/153178909-8eebb0ce-b51c-49b4-8b74-a17919e5a12d.png#gh-light-mode-only">
        <img width="100%" alt="Modifier keys" src="https://user-images.githubusercontent.com/3000535/153179104-f4230c62-bfec-443a-bfca-32a51cf5d942.png#gh-dark-mode-only">
      </td>
    </tr>
  </tbody>
</table>

## Getting started

### Installation

#### Homebrew

```sh
$ brew install --cask linearmouse --no-quarantine
```

#### Manually

1. Download [LinearMouse](https://github.com/linearmouse/linearmouse/releases/latest/download/LinearMouse.dmg).
2. Open LinearMouse.dmg, drag & drop LinearMouse to Applications.
3. Open Applications. **Right click** LinearMouse and choose Open (to make [Gatekeeper](https://support.apple.com/en-us/HT202491) happy).

### Accessibility permission

LinearMouse requires accessibility features to work properly.
You will see an alert when LinearMouse first launches.

1. Click "Open System Preferences".
2. Click the lock to make changes.
2. Find LinearMouse in the list and toggle it on.

<p align="center">
  <img width="400" alt="Accessibility permission" src="https://user-images.githubusercontent.com/62953110/149927571-b9837b0c-6881-4ac5-88da-2a55e58caf27.png#gh-light-mode-only">
<img width="400" alt="Accessibility permission" src="https://user-images.githubusercontent.com/62953110/149927673-cd20dc90-7809-4bc4-9cbc-051f9c79c597.png#gh-dark-mode-only">
</p>

## Features

* **Reverse scrolling**: LinearMouse will reverse the scrolling direction for mice but keep the direction for trackpads. This is useful if you use both mice and trackpads.

* **Linear scrolling**: LinearMouse will disable the scrolling acceleration and provide a linear and discrete scrolling experience, just like in Windows. If your mouse doesn't have a smooth wheel, you'll like this feature.

* **Universal back & forward**: Side buttons on mice do not always work well in macOS, for example, in Safari and Xcode. LinearMouse translates side button clicks to swipe gestures so that most apps can recognize back & forward actions correctly.

* **Cursor acceleration & sensitivity**: macOS only provides the ability to configure cursor acceleration which is called tracking speed in System Preferences. Regardless of how you adjust the tracking speed, the speed curve of cursor movement may still appear strange. LinearMouse allows you to customize both cursor acceleration and sensitivity, or even completely disable cursor acceleration and sensitivity.

* **Modifier keys functionality**: You may empower your modifier keys with additional functionality, such as modifying the scrolling speed or altering the scrolling oriention.

## Build

See [BUILD.md](BUILD.md).

## Contributing

Please read the [contribution guide](CONTRIBUTING.md) before making a pull request.

Thank you to all the people who already contributed to LinearMouse!

<a href="https://github.com/linearmouse/linearmouse/graphs/contributors">
  <img src="https://opencollective.com/linearmouse/contributors.svg" />
</a>

## Credits

* [Touch](https://github.com/calftrail/Touch/) (GPLv2)
* [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix)

## Buy me a coffee

* [Ko-fi](https://ko-fi.com/lujjjh)
* [爱发电](https://afdian.net/@lujjjh)
