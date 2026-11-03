# 构建与发行

基准提交与增强版本见 `publication/UPSTREAM.json`。以下命令在仓库根目录运行；Windows 使用 `gradlew.bat`，Linux/macOS 使用 `./gradlew`。

获取子模块：

```sh
git submodule update --init --recursive
```

## PIF 日期增强版

环境：JDK 21，Android SDK 37 / Build Tools 37.0.0，NDK 30.0.16248370，CMake 4.1.2，Node 与 pnpm。完整 Java/C++ 源码保留在 zygisk；手写日期界面源码位于 `webui/public/patch-mode.js`、`patch-mode.css`，脚本位于 module。

```sh
pnpm --dir webui install --frozen-lockfile
pnpm --dir webui build
./gradlew :zygisk:assembleRelease
python publication/package_module.py --output publication-output/PlayIntegrityFix-v4.9-inject-s-dates1.2.zip
```

原 Gradle 构建会生成原生元数据常量并复制 DEX 和 SO。`module.prop` 与原生常量配套生成。Releases 提供 dates1.2 实测安装包。
