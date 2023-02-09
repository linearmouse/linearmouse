# 贡献指南

感谢你投入时间为 LinearMouse 做出贡献。

阅读我们的[行为准则](CODE_OF_CONDUCT.md)，以保持我们的社区平易近人，受到尊重。

## 构建指南

在 macOS 上构建 LinearMouse 的指南。

### 设置仓库

```sh
$ git clone https://github.com/linearmouse/linearmouse.git
$ cd linearmouse
```

### 配置代码签名

Apple 要求代码签名。你可以运行以下命令来生成代码签名配置。

```
$ make configure
```

> 注：如果你希望为 LinearMouse 贡献代码，请不要在 Xcode 中直接修改“Signing & Capabilities”。使用 `make configure` 或者修改 `Signing.xcconfig`。

如果在你的钥匙串中没有代码签名证书，会生成一份使用 ad-hoc 证书签名应用的配置。

使用 ad-hoc 证书，你需要为每次构建[授予辅助功能权限](https://github.com/linearmouse/linearmouse#accessibility-permission)。因此，推荐使用 Apple Development 证书。你可以[在 Xcode 中](https://help.apple.com/xcode/mac/current/#/dev154b28f09) 创建 Apple Development 证书，这是完全免费的。

### 构建

现在，你可以运行以下命令来构建和打包 LinearMouse 了。

```sh
$ make
```
