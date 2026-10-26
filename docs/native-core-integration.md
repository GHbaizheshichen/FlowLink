# Native core 接入记录

## 当前链路

订阅下载 → URI / Base64 解析 → 选择 VLESS 节点 → Want 启动独立 VPN 扩展 →
保护扩展进程并记录物理网络 → Xray 配置加载与节点 HTTPS 探测 → 系统创建 IPv4 TUN →
Hev 将 TCP/UDP 转为本地 SOCKS → Xray VLESS / REALITY / Vision → 上游节点。

系统 TUN 创建成功后，UI 进程另外发起 HTTPS 请求；只有返回的出口 IP 与节点探测匹配、
且 native TUN 的收发计数都大于零，才确认连接并启动 DATA_TRANSFER 后台任务。
验证失败销毁本次 TUN 和内核，避免留下无法转发的系统路由。

## 鸿蒙适配

- 采用 OpenHarmony Go 1.26.5 移植及 arm64 TLSDESC 动态加载支持，不能直接打包 Android c-shared 产物。
- Xray 版本为 26.7.28，固定提交及传递依赖见 `native/xray/go.mod` / `go.sum`。
- Go 出站通过 Xray 的公开 dialer controller 调用 NDK `OH_NetConn_BindSocket`，显式绑定 VPN 建立前检查过的非 VPN 网络。
  单独调用 `protectProcessNet()` 不足以覆盖这里 Go 创建的全部出站 socket；未绑定时，真机出现大量循环进入 TUN 的流量与外网超时。
- 第一版使用单 VPN 的 `create(config)` / `destroy()`；默认路由由系统根据 IPv4 地址生成。没有并发多 VPN 支持。
- 手动配置路由时接口名称应留空让系统补齐实际 VPN 网卡名，不应写死 `tun0`。
- Hev 使用系统传入 TUN 的副本。native 停止线程后关闭副本，扩展关闭原始 fd，再销毁系统 VPN。
- 链接包装 Hev 的 run 入口，等其初始化事件管道后再确认就绪，避免刚启动便停止的竞态。
- DNS 请求在 Xray 中转至通过节点访问的 DoH；不要求上游节点承载 DNS UDP。
- 本地 SOCKS 监听 127.0.0.1:10808，并使用每次会话随机生成的密码。端口已占用时启动失败并清理。
- 通过异步 Node-API 执行内核启动、探测、TUN 初始化和停止，避免阻塞 ArkTS 的主线程。

## 真机证据（2026-10-16）

Mate 60 Pro / API 24：

- OpenHarmony Xray 动态加载成功，没有使用固定 true 作为可用状态。
- 第一份订阅：67 个受支持的节点，抽查的上游端口不可达，应用显示失败并回滚。
- 第二份订阅：导入 12 个 VLESS / REALITY / Vision 节点；另有 2 个 Shadowsocks 条目被明确跳过。
- 该订阅使用 Firefox / Safari 指纹，解析器和配置转换已保留原始指纹。
- 使用真实节点通过出口 IP 验证，首页显示“已连接”；首次成功确认时 TUN tx=4101、rx=5095 字节。
- 断开后回到“未连接”。不在此文档保存订阅 URL、节点服务器、UUID 或出口 IP。
- 再次连接成功（TUN tx=4453、rx=5311），短时切至桌面后返回应用仍保持“已连接”，随后正常断开。

本地还使用临时 REALITY 服务端验证了握手及 HTTPS 代理行为；测试配置和密钥只放在被忽略的 `.hvigor` 下，不属于应用源码或打包资源。

## 检查与边界

构建、ArkTS linter、资源检查、订阅解析回归测试，以及 Go JSON loader 测试均已执行。
详细构建命令见 README。

当前只支持 IPv4；未实现 Shadowsocks 导入、网络切换自动重连、长期稳定性测试及断线流量阻断。
出口验证依赖 api4.ipify.org 可达；该服务失败或节点使用轮换出口时，可能出现保守判定失败。
后台任务已接入，但短时切后台检查不能代替长时间锁屏、低电量和网络切换测试。

## 平台依据

使用 `devecocli docs` 核对的本地 SDK 文档：

- `@ohos.net.vpnExtension (VPN增强管理)`：TUN、VPN 配置、protectProcessNet、销毁接口与路由接口名说明。
- `应用切换到后台后VPN功能保活的解决方案`：KEEP_BACKGROUND_RUNNING 与 DATA_TRANSFER。
- SDK NDK `network/netmanager/net_connection.h`：GetDefaultNet、GetNetCapabilities 与 BindSocket。

上游构建和许可信息见 `native/THIRD_PARTY_NOTICES.md`；Go 根证书回退机制采用
[Go x509roots/fallback](https://pkg.go.dev/golang.org/x/crypto/x509roots/fallback)。
