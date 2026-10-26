# 首个订阅的兼容性检查

检查日期：2026-10-15。本次读取成功，HTTP 200，响应为 text/plain。以下为当次响应的脱敏汇总，节点数量和配置可能随订阅更新变化。

## 检查结果

| 项目 | 结果 |
| --- | --- |
| 外层格式 | Base64 编码文本 |
| 解码内容 | 每行一个 VLESS URI |
| 记录数量 | 67 |
| 代理协议 | VLESS |
| 传输 | TCP |
| 安全层 | REALITY |
| flow | xtls-rprx-vision |
| fingerprint | chrome |
| VLESS encryption | none |
| 无法识别的记录 | 0 |

67 条记录均通过本轮基本字段检查：服务器与显式端口、UUID 格式、SNI 存在、REALITY 公钥解码为 32 字节、short ID 为合法长度的十六进制文本、fingerprint 存在。

这些检查只验证配置结构，不证明公钥与服务端匹配、凭据有效或节点在线。本轮没有连接节点，也没有执行出口 IP 测试。

## 首版实现范围

1. 有界下载订阅，处理 HTTP 状态、超时与重定向。
2. Base64 解码和逐行 VLESS URI 解析，正确处理百分号编码与节点名称。
3. 扩充规范化节点模型：UUID、encryption、flow、transport、REALITY serverName/publicKey/shortId、uTLS fingerprint；显式处理未支持的参数。
4. 先支持当前样本中的 VLESS + TCP + REALITY + Vision，不静默降级到普通 TLS 或无 flow。
5. 以虚构节点编写解析测试；真实订阅内容和认证信息不进入源码或测试样例。
6. 生成目标 core 的出站配置，先验证一个节点，再接入鸿蒙 TUN 与完整会话生命周期。

## Core 接入方向

优先验证 Xray-core 的鸿蒙移植。其官方 REALITY 示例涵盖本次订阅使用的 VLESS、REALITY、Vision 与 chrome 指纹组合：

- [Project X](https://xtls.github.io/)
- [REALITY 官方示例](https://github.com/XTLS/REALITY/blob/main/README.en.md)

备选评估 sing-box，其官方文档包含 VLESS Vision、TLS/REALITY 和 TUN 相关配置：

- [VLESS 出站](https://sing-box.sagernet.org/configuration/outbound/vless/)
- [TLS / REALITY](https://sing-box.sagernet.org/configuration/shared/tls/)
- [TUN 入站](https://sing-box.sagernet.org/configuration/inbound/tun/)

协议支持与 HarmonyOS 平台支持是两个验证项。尚未验证任何候选的 HarmonyOS arm64 构建、加载、外部 TUN fd、出站保护、DNS、停止清理及许可证集成要求。保持现有 Native 桥接的 available=false，直到真实会话验证通过。

## 数据边界

此文不包含订阅地址、UUID、节点域名、SNI、节点名称或认证参数值。订阅原文仅用于本机被忽略目录下的检查，没有写入应用资源、默认配置或跟踪的测试文件。应用中的订阅地址仍由用户在订阅页输入。
