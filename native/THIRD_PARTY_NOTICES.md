# Native dependencies

The application builds these unmodified upstream components. Project wrappers are in
`native/xray` and `entry/src/main/cpp/proxy_core`. No third-party application UI or
GPL client code is included.

| Component | Pinned source | License |
|---|---|---|
| Xray-core | [5ca6f4b7d4dc](https://github.com/XTLS/Xray-core/tree/5ca6f4b7d4dc) | MPL-2.0 |
| Hev SOCKS5 tunnel 2.9.0 | [99cd2d5d](https://github.com/heiher/hev-socks5-tunnel/tree/99cd2d5d5dfc9b21038e977808e59a0b90b38fa0) | MIT |
| Hev SOCKS5 core | 5d37a81dc8d492d54c89aa6a00a5c4f505b75b99 | MIT |
| Hev task system | ed320fd855e84c6a0b8792db1edf5899f1584132 | MIT |
| lwIP fork | 7a246bcd7ab66f6057bcbae979ca8b11428cc459 | BSD-3-Clause |
| libyaml | efa36117a8646d26d12b58e05bac472d7854a70d | MIT |
| OpenHarmony Go toolchain | [19667c7a](https://github.com/star4277/ohos-go/tree/19667c7abfc332f848b5bd1f293e4aeb0e9991a9) | BSD-3-Clause and bundled notices |

Go dependency versions and integrity hashes are recorded in `native/xray/go.mod`
and `go.sum`. This includes the Go project's X.509 fallback roots (BSD-3-Clause;
certificate data includes Mozilla notices). Keep that bundle up to date.

`scripts/collect-native-licenses.mjs` copies upstream license and notice files into
the app's raw resources and records the source module versions. The build script
runs this step before packaging. Preserve these files when distributing a binary.
The linked Xray revision supplies the corresponding MPL source; retain this source
reference and make any future modifications to its covered files available under MPL.
