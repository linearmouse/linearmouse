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
        <img width="100%" alt="General" src="https://user-images.githubusercontent.com/3000535/168758303-3312414e-7ad7-4348-ac5f-574085cf9353.png#gh-light-mode-only">
        <img width="100%" alt="General" src="https://user-images.githubusercontent.com/3000535/168758499-2ea8ce75-c95f-4726-a858-aac6ca07e9df.png#gh-dark-mode-only">
      </td>
      <td width="33%">
        <img width="100%" alt="Cursor" src="https://user-images.githubusercontent.com/3000535/168758156-ebd8bf0e-afe1-4021-a092-a586cb9148a3.png#gh-light-mode-only">
        <img width="100%" alt="Cursor" src="https://user-images.githubusercontent.com/3000535/168758533-e01561a5-8a8f-438c-aebf-04974b714229.png#gh-dark-mode-only">
      </td>
      <td width="33%">
        <img width="100%" alt="Modifier keys" src="https://user-images.githubusercontent.com/3000535/168758363-b5a38104-e671-46a6-94a2-bb7538740a8a.png#gh-light-mode-only">
        <img width="100%" alt="Modifier keys" src="https://user-images.githubusercontent.com/3000535/168758566-fb00c040-6e75-4214-b121-f9f113f388e0.png#gh-dark-mode-only">
      </td>
    </tr>
  </tbody>
</table>

## Getting started

### Installation

#### Homebrew

```sh
$ brew install --cask linearmouse
```

#### Manually

1. Download [LinearMouse](https://github.com/linearmouse/linearmouse/releases/latest/download/LinearMouse.dmg).
2. Open LinearMouse.dmg, drag & drop LinearMouse to Applications.
3. Open Applications. **Right click** LinearMouse and choose Open (to make [Gatekeeper](https://support.apple.com/en-us/HT202491) happy).

### Accessibility permission

See [ACCESSIBILITY.md](ACCESSIBILITY.md).

## Features

* **Reverse scrolling**: LinearMouse will reverse the scrolling direction for mice but keep the direction for trackpads. This is useful if you use both mice and trackpads.

* **Linear scrolling**: LinearMouse will disable the scrolling acceleration and provide a linear and discrete scrolling experience, just like in Windows. If your mouse doesn't have a smooth wheel, you'll like this feature.

* **Universal back & forward**: Side buttons on mice do not always work well in macOS, for example, in Safari and Xcode. LinearMouse translates side button clicks to swipe gestures so that most apps can recognize back & forward actions correctly.

* **Cursor acceleration & sensitivity**: macOS only provides the ability to configure cursor acceleration which is called tracking speed in System Preferences. Regardless of how you adjust the tracking speed, the speed curve of cursor movement may still appear strange. LinearMouse allows you to customize both cursor acceleration and sensitivity, or even completely disable cursor acceleration and sensitivity.

* **Modifier keys functionality**: You may empower your modifier keys with additional functionality, such as modifying the scrolling speed or altering the scrolling oriention.

## Build

See [BUILD.md](BUILD.md).

## Contributing

Please read the [contributing guide](CONTRIBUTING.md) before making a pull request.

Thank you to all the people who already contributed to LinearMouse!

<a href="https://github.com/linearmouse/linearmouse/graphs/contributors">
  <img src="https://opencollective.com/linearmouse/contributors.svg" />
</a>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=linearmouse/linearmouse&type=Date)](https://star-history.com/#linearmouse/linearmouse&Date)

## Credits

* [Touch](https://github.com/calftrail/Touch/) (GPLv2)
* [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix)

## Buy me a coffee

* [Ko-fi](https://ko-fi.com/lujjjh)
* [爱发电](https://afdian.net/@lujjjh)
