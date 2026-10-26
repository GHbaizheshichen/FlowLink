# IPv6 实现与验证

日期：2026-10-21。双栈代码已接入，IPv4 真机回归通过；公网 IPv6 端到端验证尚未完成。用户确认当前没有已知可用的 IPv6 出口节点，因此不将代码接入或本地测试表示为公网验收通过。

## 改动

1. `TunnelConfig.ets` 统一系统与 Hev 的 TUN 参数：IPv4 地址 `198.18.0.1/30`，IPv6 ULA 地址 `fdfe:dcba:9876::1/126`，MTU 1500。系统开启两个协议族，并显式配置 `0.0.0.0/0` 与 `::/0`，使用系统选择的 VPN 网卡，不硬编码网卡名称。
2. Xray DNS 从 `UseIPv4` 改为 `UseIP`，允许 A 与 AAAA 查询；VPN DNS 同时配置 IPv4、IPv6 地址。保留现有经代理的 DoH 与 DNS 路由，Hev 配置加入相同的 IPv6 TUN 地址。
3. Hev/lwIP 已包含 IPv6 实现；增加编译期断言，确保未来构建不能静默关闭任一协议族。原有回环 SOCKS 仍使用 IPv4 监听，这只影响本机 Hev 到 Xray 的连接，不限制 SOCKS 中携带的 IPv6 目标。
4. Native 并行执行 IPv4、IPv6 出口探测。`HPProbe` 现在返回 JSON：`{"ipv4":"...","ipv6":"..."}`，至少一个族成功才继续连接。两个探测均有 20 秒 HTTP 超时，失败族保留空值，不伪造能力。
5. UI 进程分别请求可用族的探测端点，经系统 TUN 比较出口；IPv6 规范化后比较，避免压缩写法或大小写不同造成误判。拒绝 zone ID、IPv4 映射地址及格式错误结果。
6. Native 从 TUN 包的 IP 版本字段累计 `tx4/rx4/tx6/rx6`，只有每个声称可用的协议族均出现双向 TUN 流量，才确认连接成功。原有总计数保留。
7. 会话事件增加 IPv6 出口，首页分别展示 IPv4、IPv6 结果；未通过探测时显示对应提示。文字已提供中英文资源。

当前目标包括两种不同能力：把应用的 IPv6 流量通过代理转发，以及使用 IPv6 地址作为上游节点地址。订阅解析已接受带方括号的 IPv6 节点 URI，送入 Xray 前去掉地址方括号；该分支增加了回归用例。IPv6 地址作为上游传输地址时，设备底层网络仍需能到达该地址。

## 能力与失败规则

| Native 出口探测 | 后续行为 |
| --- | --- |
| IPv4 与 IPv6 都成功 | 两个协议族均须完成系统 TUN HTTPS 比对及字节计数验证 |
| 只有 IPv4 成功 | 验证 IPv4，允许使用，IPv6 提示探测未通过 |
| 只有 IPv6 成功 | 验证 IPv6，允许使用，IPv4 提示探测未通过 |
| 两者都失败 | 清理会话并反馈连接失败 |
| Native 声称可用，但对应系统 TUN 验证失败 | 整个连接失败并清理，不能降级后仍标为该族验证成功 |

无论哪个出口探测成功，系统 TUN 都配置双栈默认路由。未通过的协议族不被排除到物理网络作为应用级回退；是否存在系统路由例外仍需专项测试，本文不承诺全面防泄漏或断线阻断。

“探测未通过”可能来自节点出口、探测服务可达性、DNS 或超时，并不直接等于“节点一定不支持 IPv6”。单个外部探测服务的结果不是全部 IPv6 站点的可用性保证。

系统 TUN 之外的 VPN 进程出站继续使用现有 `protectProcessNet` 与底层网络 socket 绑定。新增代码没有放宽证书验证、对外开放本地 SOCKS 端口或将节点凭据写入事件。

## 验证结果

| 检查 | 结果 | 覆盖与限制 |
| --- | --- | --- |
| ArkTS 配置／解析回归 | 通过 | IPv6 节点 URI、双栈地址及默认路由、AAAA 策略、Hev 地址一致性、IPv6 规范化与错误输入 |
| Go 单元与配置测试 | 通过 | 响应族校验、HTTP 错误、超长响应、IPv4 映射地址、单族／双族／双失败结果、双栈 DNS 配置加载 |
| Go IPv6 TCP 集成测试 | 通过 | 使用真实 IPv6 loopback listener，并通过 Xray freedom 出站完成 HTTP 请求；这是本机 IPv6/Xray 测试，不代替 VLESS + TUN 公网测试 |
| OpenHarmony Native 交叉编译 | 通过 | 重新构建 Go c-shared 库并检查 TLSDESC；与 ArkTS 和 C++ 共同打包 |
| 资源完整性检查 | 通过 | 146 个中英文字符串、39 对主题颜色，资源引用与 V2 检查 |
| 签名构建与安装 | 通过 | Mate 60 Pro，API 24；保留编译器原有异常／权限静态提示 |
| HK+02 真机连接 | IPv4 通过 | 出口比对成功；TUN 记录 tx4=4150、rx4=9719，IPv6 出口探测未通过 |
| HK+01 真机连接 | IPv4 通过 | 出口比对成功；TUN 记录 tx4=1928、rx4=3990，IPv6 出口探测未通过 |
| JP+01 真机连接 | 未通过 | 本轮连接失败，不作为双栈成功证据 |
| 断开 | 通过 | 已验证返回未连接状态，测试会话已停止 |
| 公网 IPv6、IPv6 地址上游及 IPv6-only 底层网络 | 待验证 | 当前无已知可用节点，不能声称完成 |

已测会话虽然出现少量 IPv6 TUN 字节，但没有通过 IPv6 公网探测，因此没有将这些字节当作 IPv6 Internet 已可用的证据。没有在本记录中保存真实订阅、节点凭据或出口地址。

测试命令：

```powershell
node scripts/test-subscription.mjs
node scripts/check-resources.mjs
node scripts/check-ui-resources.mjs
# 使用项目 .native-cache/go 中的标准 Go；GOROOT/GOMODCACHE 等见本地构建环境
$env:CGO_ENABLED = '0'
go -C native/xray test -v ./...
./scripts/build-xray.ps1
devecocli run --device '<已连接的设备>'
git diff --check
```

`HPProbe` 的结果结构已改变，必须将重新构建的 `libharmony_xray.so`、C++ 桥接库与 ArkTS 同时部署，不能仅替换界面代码而保留旧 Native 库。

## 公网补验步骤

1. 准备已知支持 IPv6 出口、且与当前 VLESS + TCP + REALITY + Vision 组合兼容的节点，记录测试环境，不公开订阅凭据。
2. 连接后确认首页有真实 IPv6 出口，UI 进程的 IPv6-only HTTPS 校验成功，且 `tx6/rx6` 都大于零。
3. 分别验证 IPv4、IPv6-only 与双栈目标；单独验证 IPv6 UDP、DNS AAAA、大包／MTU与超时，不用 HTTPS 成功推断全部 UDP 或 ICMP 能力。
4. 覆盖 IPv6 地址上游、底层网络 IPv4-only／双栈／IPv6-only、网络变化、取消、断开及进程重启。
5. 记录系统路由、出口与资源回收证据，完成后再更新产品支持声明。

## 诊断执行记录

本轮使用 `deveco-cli` 与 `harmony-next` 技能。策略为 automation，目标为已连接测试手机；诊断为有界 UI 操作、应用安装启动及仅本应用标签的日志读取，命令等待由执行工具管理，无后台日志采集进程。

产物目录：`docs/verification/ipv6-20261021/`。脱敏规则：不保存真实订阅、完整配置、设备唯一标识或出口地址；仅保存命令类别、阶段与非敏感结果。低层 `ip` 命令在本机不可用，因此未把原始路由表检查记为通过。未修改系统网络设置或解锁设备。

## 参考

- 鸿蒙本地文档：`@ohos.net.vpnExtension` 的 VpnConfig、`@ohos.net.connection` 的 NetAddress／RouteInfo；IPv6 family 为 2，IPv6 默认路由为 `::/0`。
- [ipify 官方 API 说明](https://www.ipify.org/)：`api6.ipify.org` 为 IPv6-only 探测端点，避免双栈端点回落至 IPv4 后误判。
- 项目固定版本的 Hev/lwIP 与 Xray 源码；本轮没有升级第三方内核版本。
