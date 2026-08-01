# macOS App 打包与跨电脑运行经验

这份文档记录一次典型问题：在开发机上可以运行的菜单栏 App，直接把 `.app` 拷贝到另一台 Mac 后，双击没有反应，菜单栏也看不到图标。

## 一、先区分三种“能运行”

macOS App 的运行状态至少有三个层次：

1. **源码或开发构建能运行**：说明代码和当前开发环境基本正常。
2. **App Bundle 能被系统启动**：说明包结构、架构、系统版本和启动入口都正确。
3. **其他用户的 Mac 能安全打开**：还需要正确的 Developer ID 签名、Hardened Runtime 和 Apple 公证。

开发机上的成功，只能证明第一层，不能直接证明可以分发。

## 二、开发包和发布包不是一回事

本项目的 `script/build_and_run.sh` 用于本地开发。它生成的 `dist/HeadUp.app`：

- 默认只按当前机器构建；在 Apple Silicon 开发机上通常只有 `arm64`。
- 使用 ad hoc 签名（`codesign --sign -`），没有开发者团队身份。
- 适合本机调试，不适合直接发给其他人。

发布脚本 `script/package_release.sh` 才负责：

- Release 构建；
- 同时生成 `arm64` 和 `x86_64`；
- Developer ID 签名；
- Hardened Runtime；
- Apple notarization；
- 生成可分发的 ZIP 和校验文件。

因此，不要把开发脚本生成的 `dist/HeadUp.app` 当作最终发行包。正式发布应使用脚本生成的 `dist/release/HeadUp-版本号.zip`。

## 三、arm64、x86_64 和 Universal Binary

一个 Mach-O 可执行文件可以包含多个架构切片，这种文件叫 Universal Binary 或 Fat Binary。

- Apple Silicon Mac 使用 `arm64` 切片；
- Intel Mac 使用 `x86_64` 切片；
- 同一个 `.app` 就可以同时支持两类 Mac。

检查某个 App 的架构：

```bash
lipo -archs /path/to/HeadUp.app/Contents/MacOS/HeadUp
```

预期的通用版本输出类似：

```text
x86_64 arm64
```

如果输出只有 `arm64`，Intel Mac 无法运行；如果只有 `x86_64`，Apple Silicon Mac 会通过 Rosetta 运行。

很多应用分别提供 Intel 包和 Apple Silicon 包，主要是为了减小下载体积、简化构建或适配某些不能同时链接两种架构的第三方依赖。分成两个包不是 macOS 的强制要求。

## 四、为什么双击后像“完全没反应”

### 1. 架构不匹配

当前开发包检查结果是：

```text
Mach-O 64-bit executable arm64
```

如果目标电脑是 Intel Mac，系统会在真正启动前拒绝它。

### 2. 系统版本太低

项目的最低系统版本是 macOS 14：

```xml
<key>LSMinimumSystemVersion</key>
<string>14.0</string>
```

同时，Mach-O 的 deployment target 也应保持一致。目标 Mac 低于 macOS 14 时，App 不应认为可以运行。

### 3. 只有 ad hoc 签名

开发包的签名信息会类似：

```text
flags=0x2(adhoc)
TeamIdentifier=not set
Signature=adhoc
```

ad hoc 签名可以帮助本地开发时维持稳定的 App 身份，但它不是面向用户分发的信任签名。拷贝、下载或解压后，Gatekeeper 可能阻止启动。

检查签名：

```bash
codesign -dvvv --entitlements :- /path/to/HeadUp.app
codesign --verify --deep --strict --verbose=4 /path/to/HeadUp.app
```

检查 Gatekeeper：

```bash
spctl -a -vv --type execute /path/to/HeadUp.app
```

`codesign --verify` 显示“valid on disk”只代表文件的内部签名完整，不代表 Apple 信任这个开发者，也不代表已经公证。

### 4. 菜单栏 App 本来就不显示 Dock 图标

菜单栏 App 常使用：

```xml
<key>LSUIElement</key>
<true/>
```

这表示它不显示普通 Dock 图标。应用如果启动失败，用户就会同时看不到 Dock 图标和菜单栏图标，看起来像双击没有任何反应。

因此排查菜单栏 App 时，不要只观察 Dock；应同时检查进程和系统日志。

## 五、推荐的发布流程

正式分发前至少完成以下步骤：

```bash
swift test

HEADUP_SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" \
HEADUP_NOTARY_PROFILE="headup-notary" \
./script/package_release.sh
```

发布脚本需要：

1. Developer ID Application 证书；
2. Apple Developer Team ID；
3. `notarytool` 使用的 Apple 凭据；
4. 完整 Xcode 和可用的 macOS SDK。

发布后检查：

```bash
lipo -archs dist/release/HeadUp.app/Contents/MacOS/HeadUp
codesign -dvvv dist/release/HeadUp.app
codesign --verify --deep --strict --verbose=4 dist/release/HeadUp.app
spctl -a -vv --type execute dist/release/HeadUp.app
```

最后用 `ditto` 生成 ZIP，并分发 ZIP，而不是通过某些文件同步工具直接复制 App 目录：

```bash
ditto -c -k --sequesterRsrc --keepParent \
  dist/release/HeadUp.app \
  dist/release/HeadUp.zip
```

公证完成后还应使用 `stapler` 将公证票据附加到 App，并再次执行 `spctl` 验证。项目的 `script/package_release.sh` 已经包含这一流程。

## 六、另一台 Mac 上的排查清单

在目标电脑上依次确认：

```bash
sw_vers -productVersion
uname -m

lipo -archs /path/to/HeadUp.app/Contents/MacOS/HeadUp
plutil -p /path/to/HeadUp.app/Contents/Info.plist
codesign -dvvv /path/to/HeadUp.app
spctl -a -vv --type execute /path/to/HeadUp.app
xattr -lr /path/to/HeadUp.app
```

判断原则：

- Intel Mac 必须有 `x86_64` 切片；
- Apple Silicon Mac 最好有 `arm64` 切片；
- 系统版本必须满足 `LSMinimumSystemVersion`；
- `TeamIdentifier` 不应为空；
- 正式发行包应能通过 `spctl`；
- 如果存在 `com.apple.quarantine`，说明文件经过下载或隔离标记，Gatekeeper 会参与判断。

如果只是给自己的测试机验证，可以在 Finder 中右键 App，选择“打开”，查看系统给出的具体提示。不要把移除 quarantine 当作正式发布方案；正式方案仍然是 Developer ID 签名和公证。

## 七、最重要的结论

“在我的 Mac 上能打开”只说明开发环境可运行；“可以复制给其他 Mac”要求同时满足：

```text
正确的 App Bundle
  + 正确的最低系统版本
  + 目标架构或 Universal Binary
  + Developer ID 签名
  + Hardened Runtime
  + Apple 公证
  + ZIP 打包与发布验证
```

菜单栏图标不出现，往往只是最后的表象。真正的原因通常发生在菜单栏代码执行之前：系统尚未允许 App 启动，或者 App 在初始化阶段已经退出。
