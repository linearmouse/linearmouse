<h1 align="center">
  <a href="https://linearmouse.org/">
    <img src="logo.svg" width="128" height="128" />
    <br />
    LinearMouse
  </a>
</h1>

<p align="center">
  <a href="https://github.com/lujjjh/LinearMouse/releases/latest"><img alt="GitHub release (latest SemVer)" src="https://img.shields.io/github/v/release/lujjjh/LinearMouse?sort=semver"></a>
  <a href="https://github.com/lujjjh/LinearMouse/releases/latest/download/LinearMouse.dmg"><img src="https://img.shields.io/github/downloads/lujjjh/LinearMouse/total" alt="Downloads" /></a>
  <img src="https://img.shields.io/github/license/lujjjh/LinearMouse" alt="MIT License" />
  <a href="https://crowdin.com/project/linearmouse"><img src="https://badges.crowdin.net/linearmouse/localized.svg" alt="Crowdin" /></a>
</p>

LinearMouse is a free and open-source utility for macOS which aims to
improve the experience and functionality of third-party mice.

## Screenshots

<table>
  <tbody>
    <tr>
      <td width="33%">
        <img width="612" alt="General" src="https://user-images.githubusercontent.com/3000535/145600150-59edf92c-2911-42e3-b525-29d50aa937d6.png#gh-light-mode-only">
        <img width="612" alt="General" src="https://user-images.githubusercontent.com/3000535/145601535-41053260-f262-4e68-a81f-4b73b990570f.png#gh-dark-mode-only">
      </td>
      <td width="33%">
        <img width="612" alt="Cursor" src="https://user-images.githubusercontent.com/3000535/145600298-24a75b1a-2e15-4ebd-aa22-a30f8eb5b6db.png#gh-light-mode-only">
        <img width="612" alt="Cursor" src="https://user-images.githubusercontent.com/3000535/145601559-81e19237-1eca-4dc0-beaa-4c2028298fc7.png#gh-dark-mode-only">
      </td>
      <td width="33%">
        <img width="612" alt="Modifier keys" src="https://user-images.githubusercontent.com/3000535/145600467-6c579420-6c3e-49d4-a8ad-e1a0bd3d52c0.png#gh-light-mode-only">
        <img width="612" alt="Modifier keys" src="https://user-images.githubusercontent.com/3000535/145601581-295bd047-b0e1-4e3e-90b5-a246481c72b3.png#gh-dark-mode-only">
      </td>
    </tr>
  </tbody>
  <tfoot>
    <tr>
      <th>Reverse scrolling, Linear scrolling, Universal back & forward</th>
      <th>Cursor acceleration & sensitivity</th>
      <th>Modifier keys functionality</th>
    </tr>
  </tfoot>
</table>

## Getting started

### Installation

#### Homebrew

```sh
$ brew install --cask linearmouse --no-quarantine
```

#### Manually

1. Download [LinearMouse](https://github.com/lujjjh/LinearMouse/releases/latest/download/LinearMouse.dmg).
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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

<a href="https://github.com/linearmouse/linearmouse/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=linearmouse/linearmouse" />
</a>

## Build

See [BUILD.md](BUILD.md).

## Credits

* [Touch](https://github.com/calftrail/Touch/) (GPLv2)
* [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix)

## Buy me a coffee

* [Ko-fi](https://ko-fi.com/lujjjh)
* [爱发电](https://afdian.net/@lujjjh)
