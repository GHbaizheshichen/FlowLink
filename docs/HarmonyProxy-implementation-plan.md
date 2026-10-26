# HarmonyProxy 第一版实施方案

核对日期：2026-10-15。本文基于 `devecocli 1.3.0-stable` 本地文档检索、当前工程配置和本机 SDK 声明整理。文档随工具安装，不等同于联网获取的最新文档；接口存在不等于当前设备已经验证可用。

后续进展（2026-10-16）：三页界面、订阅下载与解析、Xray + Hev、TUN 生命周期和跨进程会话状态均已接入，真实 VLESS / REALITY / Vision 节点已在 API 24 真机通过出口 IP 和 TUN 双向流量验证。页面继续使用 Navigation + NavPathStack + NavDestination、V2 状态与资源化主题。下面的“当前结果”保留方案制定时的基线；实际范围见仓库 README 和 [Native 接入记录](native-core-integration.md)。

## 1. 已确认的工程与设备基线

| 项目 | 当前结果 |
| --- | --- |
| 应用包名 | `com.example.hmproxy` |
| 工程模型 | Stage，单 entry 模块 |
| targetSdkVersion | `26.0.0` |
| compatibleSdkVersion | `6.1.1(24)` |
| 本机 SDK | HarmonyOS 26.0.0，版本 `26.0.0.105` |
| 已连接设备 | HUAWEI Mate 60 Pro，`API 24 (Release)` |
| 应用签名 | 当前 `signingConfigs` 为空，部署前需要配置 |
| VPN / Native 配置 | 方案制定时尚未配置；后续已补 VPN Extension、网络权限和 externalNativeOptions |
| 备份 | 模板允许备份，后续需明确排除订阅凭据和节点密钥 |

第一版以当前 API 24 真机为运行基线，保留工程的 target 26 配置。26.0.0 新接口不进入必需调用路径。暂不扩大到旧版本系统或多 VPN 并行场景。

## 2. 平台能力与版本依据

以下是文档事实，来源编号见末尾。

| 能力 | 接口 / 配置 | 版本与约束 |
| --- | --- | --- |
| 第三方 VPN 入口 | `VpnExtensionAbility`，`type: "vpn"` | API 11 起，Stage 模型；独立扩展进程 [S1][S2][S3][S5] |
| 启停扩展 | `startVpnExtensionAbility(want)`、`stopVpnExtensionAbility(want)` | 首次连接有系统信任弹窗；只能停止自己应用的扩展 [S1][S2] |
| 首次启动参数 | `Want.parameters` | API 22 起支持首次 VPN 启动时传递 [S2] |
| VPN 对象 | `createVpnConnection(this.context)` | 先启动扩展，使用 VPN 扩展自己的上下文 [S2][S3] |
| TUN | `VpnConnection.create(config): Promise<number>` | 返回虚拟网卡 fd；系统只提供网卡、路由等基础能力 [S1][S2] |
| 单 socket 保护 | `protect(socketFd)` | 被保护 socket 使用物理网络，绕过 VPN [S2] |
| 进程保护 | `protectProcessNet()` | API 22 起；被保护进程使用物理网络 [S2] |
| VPN 标识 | `generateVpnId()`、`VpnConfig.vpnId` | API 20 起；第一版串行管理一个会话 [S2] |
| 清理 | `destroy()` / `destroy(vpnId)`、扩展 `onDestroy()` | 创建、销毁和扩展生命周期配对管理 [S2][S3] |
| 授权结果回调 | `createVpnObserver()`、`onAuthorizationResult()`、`offAuthorizationResult()` | 26.0.0 起，不能在 API 24 无条件调用 [S2] |

启动 API Promise 成功、扩展启动、TUN 就绪、内核就绪、实际请求成功是不同事件。UI 必须分别记录，不能用一个布尔值覆盖全部状态。

平台指南说明：调用启动接口的应用进程退出，或 VPN 服务进程销毁，系统会主动停止 VPN。[S1] 扩展进程异常终止后不能依赖 `onDestroy()` 必然执行，应重新核对系统和内核状态。[S4]

## 3. 推荐架构（工程设计）

```text
UI 主进程
  页面 / 订阅下载解析 / 节点存储 / VpnManager / BackgroundTaskController
       │
       ├── 系统 start / stop API
       ├── 首次启动 Want：会话 ID + 选中节点的有界配置快照
       └── 定向公共事件：状态查询 / 状态快照 / 停止准备
                         │
VPN 扩展进程             ▼
  ProxyVpnAbility → VpnSession → VpnConnection
                         │
                         ├── protectProcessNet()
                         ├── create(VpnConfig) → TUN fd
                         └── Node-API → NativeBridge → proxy_core
                                                        │
被代理应用 → VPN 路由 → TUN → 用户态 TCP/IP 栈 → 代理协议 → 上游节点 → Internet
```

### 3.1 进程与消息边界

- UI 单例、AppStorage、Emitter 不能作为两个进程间的通信通道。Emitter 仅作用于同一进程。[S10]
- 节点仓库先由 UI 进程持有；启动时通过 Want 传递选中节点的配置快照，不传整份订阅。限制配置大小，拒绝超长输入，不把配置写入日志。
- 在调用启动 API 前订阅状态事件。扩展单独发布启动阶段、内核状态、流量摘要和错误。
- 第一版用定向 `commonEventManager` 做轻量控制与状态查询：发布时指定本应用 `bundleName`，订阅时指定 `publisherBundleName`。[S11][S12]
- 消息含 `sessionId`、`requestId`、递增 `revision`。UI 丢弃旧会话或乱序快照；公共事件不携带密码、token、原始订阅和 TUN fd。
- 公共事件是通知通道，不视为可靠持久队列；UI 回前台时主动查询实时快照。有限超时后显示“状态未确认”，不能继续展示旧的“已连接”。控制消息需处理超时和重复接收。
- TUN fd 始终留在扩展进程，直接传给同进程 native。跨进程传一个整数不能转移 fd 所有权。

### 3.2 上游连接保护

优先验证：在扩展进程中调用 `protectProcessNet()`，成功后再启动内核、进行上游域名解析与连接。它能减少第三方内核逐个暴露 socket fd 的适配工作；API 24 满足文档标注的版本条件，实际覆盖 native TCP、UDP、重连及网络切换仍需真机验证。

若该方式在目标内核中验证失败，再采用逐 socket 方案：native 创建 socket → 回到 ArkTS 调用 `protect(fd)` → 等待成功 → 发起连接或发送。DNS 引导连接、新建连接、UDP 和重连必须覆盖；保护失败时终止该连接。

不能把 TUN fd 传给 `protect()`；不能通过排除整个应用包名替代精确的进程设计。保护扩展进程后，它自身的普通 IP 查询会直连物理网络，出口验收必须来自被代理的独立应用或明确经过代理通道的探测。

### 3.3 Native 边界

Node-API 提供初始化、启动、停止、状态查询和回调。永久读写循环放在 native 工作线程；工作线程通过线程安全函数回到创建回调的 ArkTS 线程，不能直接跨线程使用 `napi_env` / `napi_value`。[S9]

建议桥接契约（自定义，不是鸿蒙系统 API）：

```text
prepare(config, onEvent) → Promise<CoreCapabilities>
start(tunFd, sessionId)  → Promise<void>
stop(sessionId)         → Promise<void>
getSnapshot()          → CoreSnapshot
```

先约定 fd 的唯一关闭者、是否需要 dup、停止时怎样唤醒 read/poll、工作线程退出顺序和回调释放顺序。与选定内核的真实 fd 所有权一致后再实现；只传递一次，避免重复关闭。停止动作幂等、有超时，不能在 ArkTS 线程同步等待一个仍需 ArkTS 回调才能退出的 native 线程。

## 4. Native core 的选择与验证门槛

鸿蒙文档没有提供 Shadowsocks、VMess、VLESS、Trojan 或通用订阅的实现，不能从 VPN API 推导这些协议已经可用。[S1][S2]

推荐先复用已有用户态 TCP/IP 栈和代理协议实现。优先考察支持外部 TUN fd 的内核；如果协议内核只有 SOCKS 接口，则采用 TUN → tun2socks → 本地 SOCKS → 协议内核。`napi_init.cpp` 只做桥接，不能把全部网络逻辑写在入口文件。

选型先过以下门槛，再承诺支持的订阅格式和协议：

1. 能使用 HarmonyOS NDK 为 arm64 构建并装载，明确运行时和第三方依赖。
2. 能接收系统已经创建的 TUN fd，不自行打开 `/dev/tun` 或要求 root。
3. 上游连接可通过进程保护或 socket 保护，重连不形成回环。
4. 有 IPv4 TCP 数据通路与可用 DNS，明确 UDP 和 IPv6 能力。
5. 停止、再次启动、线程退出和 fd 清理可验证。
6. 许可证与后续分发方式相容。

固定测试节点可先用受控 SOCKS5 上游验证 TUN 转发；它只是移植测试入口。用户首版所支持的节点协议和订阅格式，需要以实际订阅样本与内核支持的交集确定，现阶段不承诺通用 Clash / V2Ray 兼容。

## 5. 路由、DNS 与配置约定

| 项目 | 第一版设计 |
| --- | --- |
| VPN 地址 | 使用测试网络中不冲突的私有 IPv4 地址，配置前检查是否与当前网段重叠 |
| IPv4 路由 | 显式设置 `0.0.0.0/0`；测试阶段可用 trustedApplications 仅接管独立测试应用 |
| 应用范围 | trustedApplications 与 blockedApplications 二选一；最终全局 IPv4 模式清除测试白名单 |
| MTU | 初值 1400，保持在文档范围 576–1500 内；按内核实际情况调整 |
| 网卡 / 网关 | 使用系统默认或已确认的虚拟网卡配置，不照抄示例中的 eth0 和占位网关 |
| VPN ID | 为每次会话生成并由扩展保存，失败和停止按该会话清理 |
| DNS | 配置 core 能处理的 DNS 地址，支持 UDP/TCP DNS 或由 core 转换为受控上游请求 |
| IPv6 | 第一阶段聚焦 IPv4；记录 IPv6 实际行为，未通过专项测试不宣称全流量覆盖 |
| isInternal | 保持第三方 VPN 默认语义，不当作透明转发开关 |
| isBlocking | 根据 core 的 fd I/O 模式决定，初始采用非阻塞；不当作 kill switch |

DNS 需要解决两个阶段：建立代理前解析节点域名，以及建立代理后处理被代理应用的 DNS。仅填写 `dnsAddresses` 不会自动实现 DNS 转发。文档 FAQ 还说明应用自定义 DoH、HTTPDNS 和连接复用可能绕过指定 DNS 解析路径；绕过指定解析器不等于流量必然绕过 VPN。[S6]

不要在 `dnsAddresses` 中填写任意自定义端口；FAQ 说明默认使用 53 端口。自定义内部 DNS 地址应由 core 在 TUN 中识别和处理。[S6]

### 文档冲突处理

内网路由 FAQ [S7] 把 `isBlocking` 解释成阻止非 VPN 连接，并建议设置 `isInternal`。这与 API 参考及当前 SDK 声明存在语义冲突：`isBlocking` 描述的是阻塞模式，`isInternal` 描述内置 VPN 支持。[S2]

本方案以 API 参考和 SDK 声明为接口依据，不照搬该 FAQ 的两个开关。内网转发按网段冲突、路由优先级和实际流量验证；默认路由也不能作为覆盖所有特殊网络路径的证明。

指南中“仅一个 VPN”的表述与 API 20 起的多 VPN 接口也存在范围差异。第一版串行维护一个会话，已有 VPN 冲突时明确报错，不主动销毁其他应用的 VPN。

## 6. 生命周期、后台与 UI 状态

### 启动

1. 下载/解析订阅，校验节点和协议能力；UI 用户选定节点。
2. 创建 sessionId，订阅消息，禁用重复连接操作，调用 startVpnExtensionAbility。
3. 系统请求用户信任；API 24 等待扩展的真实启动消息，不能假设存在 26.0.0 授权回调。
4. 扩展用自身 context 创建连接对象，注册控制与状态查询处理器，发布 STARTING。
5. 建立进程保护或 socket 保护策略，初始化 core，生成 vpnId。
6. 创建 TUN，立即交给已准备好的 core 开始转发；任何失败统一回滚。
7. 核心运行状态与经过代理通道的实际连通性分别记录。只有真实转发探测成功，才显示可用连接。

API 24 等待授权超过 UI 等待时限时，显示“尚未确认启动”，允许取消；超时不等于用户拒绝。取消与迟到的 onCreate 必须通过 sessionId 协调，旧会话若迟到启动应结束清理，避免用户取消后悄然建立连接。API 26 的观察者可作为后续受版本保护的增强。

### 状态

```text
IDLE → WAITING_AUTH → STARTING → TUN_READY → CORE_READY → VERIFYING → CONNECTED
                         │          │            │           │         │
                         └──────────┴────────────┴───────────┴─────────┤
                                                                      ▼
                                                               STOPPING → IDLE
失败：记录阶段、脱敏错误、系统错误码 → 清理 → ERROR
无法确认存活：UNKNOWN → 主动查询 → 实际状态
```

UI 镜像扩展进程状态；`start()` 返回成功不直接跳 CONNECTED，旧的持久化 connected 标记不作为当前事实。

### 停止和失败回滚

正常停止时先向扩展请求停止准备，让 native 停止创建新连接，唤醒并终止数据循环，按已约定所有权释放 fd/socket，再 await destroy(vpnId)，最后 stopVpnExtensionAbility。若准备无响应，执行系统停止并核对网络恢复。

扩展 onDestroy 走同一套幂等清理作为兜底；不能只在 UI 释放资源，也不能依赖进程异常退出时一定执行异步回调。切换节点先停止旧会话再启动新会话，第一版不做热切换。

### 后台

官方 VPN FAQ 明确扩展是独立进程，后台可能冻结/被回收，并给出由 UIAbility 申请 DATA_TRANSFER 长时任务的方案。[S5]

实施要求：

- 声明 KEEP_BACKGROUND_RUNNING；在 UIAbility 的 backgroundModes 声明 dataTransfer。
- 在 VPN 有活动会话且需要退后台继续传输时，由 UIAbility 申请长时任务；扩展本身不申请。通知入口打开 EntryAbility。
- 以真实流量和状态更新通知/实况窗，监听任务取消并执行连接清理；VPN 停止时释放长时任务。
- 长时任务指南要求数据传输进度更新，并说明首次更新超过 10 分钟可能取消任务；需核对实况窗接入要求及 API 24 行为。[S8]
- 验收持续传输和空闲两种场景，以及锁屏、通知删除、回前台和系统回收。长时任务不构成永不终止保证。[S5][S8]

## 7. 文件职责

```text
entry/src/main/
├── module.json5
├── ets/
│   ├── pages/{HomePage,NodePage,SubscriptionPage}.ets
│   ├── vpn/
│   │   ├── ProxyVpnAbility.ets          # 系统扩展入口
│   │   ├── VpnSession.ets               # 连接、TUN、core 和清理的唯一持有者
│   │   ├── VpnManager.ets               # UI 侧控制接口
│   │   ├── VpnMessaging.ets             # 定向控制/状态消息
│   │   └── VpnState.ets                 # 会话和状态契约
│   ├── background/BackgroundTaskController.ets
│   ├── subscription/
│   │   ├── SubscriptionClient.ets       # HTTP、超时、大小限制
│   │   ├── SubscriptionParser.ets       # 仅解析明确支持的格式
│   │   └── ProxyNode.ets                # 规范化节点与能力校验
│   ├── storage/NodeRepository.ets       # UI 侧存储
│   └── native/NativeCore.ets            # 桥接包装
└── cpp/
    ├── CMakeLists.txt
    ├── napi_init.cpp
    ├── types/libproxy_core/{index.d.ts,oh-package.json5}
    └── proxy_core/                      # 内核适配及第三方依赖
```

业务实现时还需配置 externalNativeOptions、native 模块依赖、main_pages 和权限。当前 SDK 26 构建工具使用 externalNativeOptions 字段。订阅 URL 常含 token，存储和备份规则必须与节点密码一起设计，解析/连接日志只输出脱敏信息。

## 8. 实施与验收顺序

| 阶段 | 工作 | 必须通过 |
| --- | --- | --- |
| P0 平台验证 | 签名、权限、VPN 扩展、Want 传参、跨进程消息、进程保护、TUN 生命周期 | API 24 真机能授权、启停、取消；只接管测试应用；停止恢复网络 |
| P1 内核验证 | arm64 Native 构建、固定节点、TUN TCP/IP 栈、DNS、退出清理 | 独立测试应用能通过代理访问 HTTPS；服务端确认代理出口；可反复启停 |
| P2 完整流程 | 约定格式订阅、节点列表、选择、实际协议配置转换、失败提示 | 输入地址 → 获取节点 → 选择 → 连接 → 验证出口完整可用 |
| P3 后台与恢复 | 长时任务、通知、进度、取消、网络变化、状态恢复 | 持续与空闲后台运行；锁屏；Wi-Fi/蜂窝切换；主进程和扩展异常退出后的状态一致 |

P0 和 P1 可在分应用接管下验证；P2 交付测试需要明确 IPv4 全局模式及 IPv6/UDP 边界。后台是用户可用版本的必要门槛，不能只以前台截图作为完成依据。

错误至少按阶段区分：201 权限/策略问题、16000001 Ability 不存在、16000002 Ability 类型错误、2203001 用户类型不允许、2203002 VPN 已存在、2203004 socket fd 无效、2200003 系统内部错误。系统错误码只表示诊断入口，不自动认定根因。[S2][S4]

## 9. 统一工具链

```powershell
devecocli docs search vpnExtension --format json --limit 10
devecocli docs read 'API参考/网络/Network_Kit_网络服务/ArkTS_API/ohos_net_vpnExtension_VPN增强管理_/js-apis-net-vpnextension'
devecocli check lint
devecocli build
devecocli device list --format json
devecocli run --device 'HUAWEI Mate 60 Pro'
devecocli log --device 'HUAWEI Mate 60 Pro' --bundle-name com.example.hmproxy --level E --from 5m --tail 200
```

以上构建/部署命令为后续验证流程，本轮只查文档与设备信息，没有构建、安装或更改设备网络。签名配置不完整时先完成签名准备，再执行真机安装。

## 10. 文档索引（均已用 devecocli docs read 读取）

使用 `devecocli docs read '<documentId>'` 可复核：

| 编号 | 文档 | documentId |
| --- | --- | --- |
| S1 | 连接VPN | `开发指南/网络/Network_Kit_网络服务/连接网络/连接VPN/net-vpnextension` |
| S2 | VPN增强管理 | `API参考/网络/Network_Kit_网络服务/ArkTS_API/ohos_net_vpnExtension_VPN增强管理_/js-apis-net-vpnextension` |
| S3 | VpnExtensionAbility | `API参考/网络/Network_Kit_网络服务/ArkTS_API/ohos_app_ability_VpnExtensionAbility_三方VPN能力_/js-apis-vpnextensionability` |
| S4 | VPN流程问题排查指南 | `FAQ/网络/网络_Network/VPN流程问题排查指南/faqs-network-kit-new-00001` |
| S5 | 应用切换到后台后VPN功能保活的解决方案 | `FAQ/网络/网络_Network/应用切换到后台后VPN功能保活的解决方案/faqs-network-134` |
| S6 | HarmonyOS下VPN的DNS解析顺序及域名拦截失效的处理方案 | `FAQ/网络/网络_Network/HarmonyOS下VPN的DNS解析顺序及域名拦截失效的处理方案/faqs-network-126` |
| S7 | VPN接入状态下，应用访问内网资源的流量未路由至VPN链路 | `FAQ/网络/网络_Network/VPN接入状态下_应用访问内网资源的流量未路由至VPN链路/faqs-network-135` |
| S8 | 长时任务(ArkTS) | `开发指南/Background_Tasks_Kit_后台任务开发服务/长时任务_ArkTS/continuous-task` |
| S9 | 使用Node-API接口进行线程安全开发 | `开发指南/代码开发/使用Node-API实现ArkTS_JS与C_C_语言交互/Node-API典型使用场景/使用Node-API接口进行线程安全开发/use-napi-thread-safety` |
| S10 | Emitter | `API参考/基础功能/Basic_Services_Kit_基础服务/ArkTS_API/进程线程通信/ohos_events_emitter_Emitter_/js-apis-emitter` |
| S11 | CommonEventPublishData | `API参考/基础功能/Basic_Services_Kit_基础服务/ArkTS_API/进程线程通信/commonEvent/CommonEventPublishData/js-apis-inner-commonevent-commoneventpublishdata` |
| S12 | CommonEventSubscribeInfo | `API参考/基础功能/Basic_Services_Kit_基础服务/ArkTS_API/进程线程通信/commonEvent/CommonEventSubscribeInfo/js-apis-inner-commonevent-commoneventsubscribeinfo` |

SDK 复核文件：`C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.net.vpnExtension.d.ts`，确认了 26.0.0 的观察者接口、API 22 的进程保护，以及 isBlocking/isInternal 的声明。

待实施验证：进程保护对选定内核的覆盖；状态消息在后台的投递和前台恢复；长时任务/实况窗在 API 24 上的行为；内核与真实订阅协议适配；IPv6、UDP 和网络切换。本文是实现方案，不是这些能力已经跑通的报告。
