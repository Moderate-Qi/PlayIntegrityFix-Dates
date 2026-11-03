# PIF 日期管理增强版 · v4.9-inject-s-dates1.2

下载文件：`PlayIntegrityFix-v4.9-inject-s-dates1.2.zip`

基于 PIF v4.9 inject-s，加入补丁日期模式、TS-OSS 日期联动和紧凑版 WebUI。指纹更新、日期设置、同步状态和运行输出集中在一个界面里，日常调整更方便。

## 相比原版增加

- **Google 原值／系统原值。** Google Play 服务和 Play 商店沿用 Pixel 配置中的补丁日期，系统及普通应用沿用当前固件的原始补丁日期，两套日期分别管理。
- **四种日期模式。** 支持 Google 原值／系统原值、官方原始日期、day01、自定义日期，直接在 WebUI 中选择。
- **Autopif 自动联动。** 获取新指纹时继续使用已选日期模式，指纹和日期一次更新。
- **配合 TS-OSS 管理证明日期。** 系统、Vendor 与 Boot 补丁日期按各自配置同步，Google 应用沿用独立设置。
- 
- **配置备份与开机同步。** 保存调整前的日期配置，开机后继续应用已保存模式。

## 使用方式

1. 从本仓库 Releases 下载 `PlayIntegrityFix-v4.9-inject-s-dates1.2.zip`，在 SukiSU Ultra 中刷入并重启。
2. 进入 PIF WebUI，选择“Google 原值／系统原值”，启用“同步安全补丁”。
3. 选择 Pixel 6–9 对应机型，运行 Autopif，查看下方指纹和同步输出。
4. 配合 TS-OSS、现有 keybox 与目标应用配置使用，完成同步后重启手机。
