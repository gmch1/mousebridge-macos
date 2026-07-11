# 发布 MouseBridge

[English](RELEASING.md) | 简体中文

发布流水线由语义化版本 tag 触发。Tag 必须与 `Info.plist` 中的
`CFBundleShortVersionString` 完全一致。

## 预发布版本

没有 Apple 签名 secrets 时，流水线会构建 ad-hoc 签名压缩包，并发布为 GitHub
Pre-release：

```bash
git tag -a v0.2.0 -m "MouseBridge v0.2.0"
git push origin v0.2.0
```

## 签名并公证的正式版本

推送 tag 前，在 GitHub Actions 仓库设置中配置：

- `APPLE_CERTIFICATE_P12`：Developer ID Application `.p12` 的 Base64 内容
- `APPLE_CERTIFICATE_PASSWORD`：`.p12` 密码
- `KEYCHAIN_PASSWORD`：可选的 CI 临时钥匙串密码
- `APPLE_API_KEY_P8`：App Store Connect API 私钥的 Base64 内容
- `APPLE_API_KEY_ID`：App Store Connect API Key ID
- `APPLE_API_ISSUER_ID`：App Store Connect API Issuer ID

全部必要 secrets 可用时，流水线会把证书导入临时钥匙串，应用 hardened Developer ID
签名，提交 Apple 公证，装订公证票据，然后发布普通 GitHub Release。

每个版本包含应用 ZIP 和 SHA-256 校验文件。版本校验、测试、签名、公证或打包任一步骤
失败时，Release 都不会创建。
