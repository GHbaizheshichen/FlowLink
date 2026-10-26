# 节点批量测速

日期：2026-10-21。已实现并在 Mate 60 Pro（API 24）运行验证。

## 使用方式与口径

在节点页筛选后点击“批量测速”。测试范围为点击时的筛选结果，默认没有筛选时测试全部节点。改变搜索、地区或排序不会改变已启动任务的范围。再次点击可取消。

显示值是**经所选测试节点转发的 HTTPS 小请求耗时，单位毫秒**，不是 ICMP ping、单纯 TCP 握手延迟或 MB/s 下载带宽。时间从发起请求计至读完受限的小响应，包括代理连接、目标 TLS 和请求响应，不包含队列等待和临时内核初始化。

探测目标固定为 `https://api64.ipify.org`，支持返回 IPv4 或 IPv6 地址。要求证书正常验证、HTTP 200、响应为有效 IP；不追随重定向，不把仅能建立 TCP 或返回登录页当作成功。探测结果会受节点、当前网络及目标服务影响，一次失败不等于节点永久失效。API 依据：[ipify 官方说明](https://www.ipify.org/)。

## 执行与安全边界

- ArkTS 调度与 Go 侧都限制最多 3 个测试并发，每个节点总超时 8 秒。
- 只在应用 VPN 未连接、无配置更新且内核可用时启动；Native 还检查默认网络不能是 VPN。
- Native 将 socket 绑定到底层网络，按每个节点的 VLESS + TCP + REALITY + Vision 配置创建独立 Xray 实例。测试配置没有 inbound，不监听现有 SOCKS 端口，不创建 TUN，也不切换系统 VPN。
- 测速不自动选中最快节点，保留用户当前选择。测速期间禁止连接、更换节点、更新或删除订阅；可继续搜索、排序及浏览页面，回到节点页取消。
- 取消同时取消活跃请求并停止后续任务；在所有旧工作结束前不能启动下一批。迟到的成功结果不能覆盖已取消状态。
- 完成、超时、失败或取消均关闭临时 HTTP 连接和 Xray 实例。Native 生命周期锁不跨测量请求持有，避免取消被网络请求阻塞。
- 节点配置只用于内存中的测试，不写配置文件。返回 UI 的结果仅含状态、耗时，不保留探测 IP，不记录节点凭据。

## 界面与状态

- 每行区分未知、等待中、测速中、成功毫秒值、超时、失败与已取消。
- 显示完成数／总数，完成后显示成功节点数；取消汇总的完成数不包含尚未完成的取消项。
- 提供原始顺序、按名称、按延迟三种排序。延迟排序仅将成功项按耗时升序排列，其余项置后，保留相对顺序。
- 复测当前范围会更新该范围的结果；范围外结果保留。订阅刷新成功或删除后清除旧测量结果，失败刷新保留原数据。
- 结果只保留当前进程会话，不持久化。时间与失败结果不是永久节点健康标记。
- 文案通过 resources 提供中英文，复用已有浅深色令牌与 V2 状态管理。

## 实现入口

| 文件 | 职责 |
| --- | --- |
| `entry/src/main/ets/state/LatencyBatchController.ets` | 筛选快照、并发、进度、取消、旧结果隔离 |
| `entry/src/main/ets/subscription/NodeLatency.ets` | V2 结果模型、状态、排序与测试客户端接口 |
| `entry/src/main/ets/native/XrayConfig.ets` | 无监听入口的独立测试配置 |
| `entry/src/main/ets/pages/NodePage.ets`、`components/NodeRow.ets` | 批量操作、状态和排序 |
| `native/xray/latency.go` | 有界请求、独立内核、Native 取消与并发限制 |
| `entry/src/main/cpp/napi_init.cpp`、`proxy_core/proxy_core.cpp` | 异步桥接与底层网络检查 |

新增 Native 导出必须随重新构建的 `libharmony_xray.so` 一起部署，不能只替换 ArkTS 文件而使用旧库。

## 验证记录

- `scripts/test-latency.mjs` 通过：最多 3 个工作任务、范围快照、去重及旧节点对象过滤、进度、取消后不启动队列、迟到结果、清理顺序、保持选择、VPN 状态限制与排序。
- Go 测试通过：HTTPS 正确／错误响应、实际请求超时、取消、批次互斥、取消后迟到任务及拒绝监听入口配置；现有 IPv6、配置测试一并通过。
- 订阅／配置测试与资源检查通过。161 个字符串、39 对主题颜色，V2 与引用检查有效。
- Native 交叉编译、ArkTS／C++ 签名构建、安装启动通过。编译仍有既有异常处理和剪贴板权限静态提示，不把这些提示描述为零告警。
- 真机第一批 12 个节点中 11 个成功，显示真实值，如 JP+02 946ms、JP+01 1006ms、HK+02 1152ms；这些只代表该次测试，不保证复测数值相同。
- 真机切换“按延迟”后，列表前两项显示为 946ms、1006ms；失败项后置由排序回归验证。取消测试在完成 9/12 时停止，其余任务未继续完成，按钮恢复可再次启动。
- 最终包重新安装并复测，12 个节点中 9 个成功；耗时和成功数量随网络变化，未将之前的结果作为固定值。返回首页确认选中节点仍为 HK+01。
- 测试期间未启动 VPN，原选中的 HK+01 保持不变。没有额外执行下载带宽、ICMP 或所有设备／语言／字体组合验收。

截图：[首轮排序结果](verification/latency-20261021/sorted-results.png)、[最终包结果](verification/latency-20261021/final-results.png)。

## 运行检查

```powershell
node scripts/test-latency.mjs
node scripts/test-subscription.mjs
node scripts/check-resources.mjs
node scripts/check-ui-resources.mjs
# 使用项目标准 Go 工具链，配置 GOROOT/GOMODCACHE 后运行
$env:CGO_ENABLED = '0'
go -C native/xray test ./...
./scripts/build-xray.ps1
devecocli build
devecocli run --skip-build --device '<测试设备>'
```

本轮 Windows 上系统 Node 26 在测试异常退出时出现运行时断言；调度回归最终使用已安装的 Codex 附带 Node 24 完成。与产品代码的鸿蒙运行无关。
