# HarmonyProxy

HarmonyOS Stage 代理应用，最低 API 24，当前 Native 构建目标为 arm64-v8a。

## 功能

- Navigation + NavPathStack + NavDestination 页面路由，全部使用状态管理 V2。
- 简体中文、英文和跟随系统的深浅色主题；文字与颜色均来自 resources。
- 保存订阅地址，下载 Base64 或明文节点列表；支持 VLESS + TCP + REALITY + Vision（Chrome、Firefox、Safari 指纹）。其他协议或无效条目显示跳过数量。
- 节点列表与选择，Xray 配置仅驻留内存；不把订阅凭据编译进应用或写入配置文件。
- 节点批量 HTTPS 延迟测试，最多并发 3 个、单节点超时 8 秒，支持取消、进度与按延迟排序。需先断开 VPN，不切换系统 VPN 或自动改选节点；详见 [批量测速](docs/batch-latency.md)。
- 独立 VpnExtensionAbility 进程先保护出站连接，再运行 Xray、创建 IPv4/IPv6 双栈 TUN，并交给 Hev SOCKS5 tunnel 转发。
- 本地 SOCKS 只监听回环地址，启用每次会话独立的随机密码。
- Go 出站 socket 使用公开 NDK `OH_NetConn_BindSocket` 绑定经检查的底层网络；DNS 通过节点转发至 DoH。
- 分别探测 IPv4/IPv6 出口，再从 UI 进程通过系统 TUN 校验可用协议族的 HTTPS 出口与双向字节计数；失败回滚，停止时关闭内核、TUN 和 VPN。
- 定向公共事件同步会话状态，订阅端限制发布者包名；事件不携带节点凭据。连接后申请 DATA_TRANSFER 长时任务。

IPv6 路由、AAAA DNS、Hev 转发及分协议族验证已接入；IPv6 公网可用性取决于节点出口。当前真机样本已通过 IPv4 验证，但已测节点的 IPv6 出口探测未通过，尚未完成公网 IPv6 端到端验收。单一协议族可用时仍允许连接，首页分别说明探测结果，不将 IPv4 成功表示为 IPv6 成功。细节见 [IPv6 实现与验证](docs/ipv6-support.md)。

网络切换自动重连、多 VPN 并发、其他订阅格式和协议尚未实现。未提供断线流量阻断功能。单个节点不可达时不会自动轮换全部节点。

## 构建

需要 Windows、DevEco Studio / SDK 26、Git、Node.js 和 devecocli。Hev SOCKS5 tunnel 源码已随仓库提交于 `entry/src/main/cpp/third-party`；首次准备会下载 Go 源码并构建 OpenHarmony Go 工具链，耗时数分钟，缓存位于 `.native-cache`。

```powershell
Copy-Item ./build-profile.example.json5 ./build-profile.json5
./scripts/prepare-native.ps1
devecocli build
devecocli run --device 'HUAWEI Mate 60 Pro' --skip-build
```

首次克隆后先复制构建配置模板，再通过本机 DevEco Studio 配置签名，或运行
`devecocli auth login` 和 `devecocli signature generate --product default`。
`build-profile.json5` 包含本机签名配置，已排除出版本控制；已有本地配置时不要覆盖。

后续只修改 ArkTS / C++ 时运行 `devecocli build`。修改 Go 桥接时先运行：

```powershell
./scripts/build-xray.ps1
devecocli build
```

Native 构建脚本默认使用 `https://goproxy.cn,direct`，可通过 `-GoProxy` 覆盖，模块仍通过 Go 校验和机制验证。Go 工具链固定到提交，Hev 固定到 2.9.0（99cd2d5d），下载的工具链归档验证 SHA-256。普通 Linux / Android 的 Go 动态库不适用于这里的动态加载方式；构建脚本检查 arm64 TLSDESC 重定位。

生成的 `entry/libs/arm64-v8a/libharmony_xray.so` 不提交到版本库；构建时必须存在。签名配置由本机 DevEco 管理。

## 使用

1. 在订阅页输入自己的地址，点击“保存并刷新节点”。
2. 在节点页选择节点，返回首页连接。
3. 首次连接按系统提示授权 VPN。只有外网与 TUN 验证成功后才显示“已连接”和出口 IP。
4. 点击“断开 VPN”释放本次会话。

订阅地址保存在应用私有 Preferences 中，应用备份已关闭。节点 UUID、REALITY 参数和生成的完整配置不持久化。应用诊断日志只输出固定阶段、错误代码和字节计数。

## 代码入口

| 路径 | 用途 |
|---|---|
| `entry/src/main/ets/pages` | 首页、节点、订阅和导航容器 |
| `entry/src/main/ets/state` | V2 可观测状态与控制器 |
| `entry/src/main/ets/subscription` | 下载、解析、节点模型与地址存储 |
| `entry/src/main/ets/vpn` | VPN 生命周期、进程通信与连接验证 |
| `entry/src/main/ets/native` | ArkTS 桥接和 Xray 配置转换 |
| `entry/src/main/cpp` | 异步 Node-API、Go 动态加载、Hev 工作线程 |
| `native/xray` | Xray C ABI，固定版本的 go.mod / go.sum |
| `scripts` | Native 准备、构建、许可证收集和验证 |

## 验证

```powershell
node scripts/check-resources.mjs
node scripts/test-subscription.mjs
node scripts/test-latency.mjs
devecocli check lint --format json
devecocli build
```

Go JSON 配置入口的回归测试可在安装标准 Go 1.26.5 后运行：

```powershell
$env:CGO_ENABLED = '0'
go -C native/xray test ./...
```

这组 Go 测试验证官方 JSON 加载器和错误配置处理，不代替鸿蒙 cgo / VPN 真机验证。

资源检查包含语言键、格式参数、plural、主题完整性、引用及普通启用文字对比度，当前最低 4.75:1。

上游版本、许可证与来源见 [Native notices](native/THIRD_PARTY_NOTICES.md)，构建脚本同时将许可证汇总打包到 rawfile。平台 API 和设计背景见 [实施方案](docs/HarmonyProxy-implementation-plan.md)。
