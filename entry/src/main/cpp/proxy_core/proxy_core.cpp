#include "proxy_core.h"
#include <dlfcn.h>
#include <unistd.h>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <atomic>
#include <sys/uio.h>
#include <network/netmanager/net_connection.h>
extern "C" {
#include "hev-main.h"
#include "lwip/opt.h"
int __real_hev_socks5_tunnel_run(void);
ssize_t __real_read(int, void*, size_t);
ssize_t __real_write(int, const void*, size_t);
ssize_t __real_readv(int, const struct iovec*, int);
ssize_t __real_writev(int, const struct iovec*, int);
}
static_assert(LWIP_IPV4 == 1 && LWIP_IPV6 == 1, "Hev/lwIP must be built with both IP families");
namespace {
std::mutex operation, readyMutex;
std::condition_variable readyCondition;
std::thread tunnel;
bool ready = false, finished = false;
std::atomic<int> tunnelFd{-1};
std::atomic<uint64_t> txBytes{0}, rxBytes{0};
std::atomic<uint64_t> tx4Bytes{0}, rx4Bytes{0}, tx6Bytes{0}, rx6Bytes{0};
void* library = nullptr;
void* residentHandle = nullptr;
char* (*version)() = nullptr;
char* (*start)(const char*) = nullptr;
char* (*probe)() = nullptr;
void (*stop)() = nullptr;
void (*release)(char*) = nullptr;
void (*setNetwork)(int) = nullptr;
char* (*beginLatency)(const char*) = nullptr;
char* (*measureLatency)(const char*, const char*) = nullptr;
void (*cancelLatency)(const char*) = nullptr;
void (*endLatency)(const char*) = nullptr;
bool Load() {
    if (library) return true;
    if (residentHandle) return false;
    void* handle = dlopen("libharmony_xray.so", RTLD_NOW | RTLD_LOCAL);
    if (!handle) return false;
    residentHandle = handle;
    version = reinterpret_cast<decltype(version)>(dlsym(handle, "HPVersion"));
    start = reinterpret_cast<decltype(start)>(dlsym(handle, "HPStart"));
    probe = reinterpret_cast<decltype(probe)>(dlsym(handle, "HPProbe"));
    stop = reinterpret_cast<decltype(stop)>(dlsym(handle, "HPStop"));
    release = reinterpret_cast<decltype(release)>(dlsym(handle, "HPFree"));
    setNetwork = reinterpret_cast<decltype(setNetwork)>(dlsym(handle, "HPSetNetwork"));
    beginLatency = reinterpret_cast<decltype(beginLatency)>(dlsym(handle, "HPBeginLatencyBatch"));
    measureLatency = reinterpret_cast<decltype(measureLatency)>(dlsym(handle, "HPMeasureLatency"));
    cancelLatency = reinterpret_cast<decltype(cancelLatency)>(dlsym(handle, "HPCancelLatencyBatch"));
    endLatency = reinterpret_cast<decltype(endLatency)>(dlsym(handle, "HPEndLatencyBatch"));
    if (!version || !start || !probe || !stop || !release || !setNetwork ||
        !beginLatency || !measureLatency || !cancelLatency || !endLatency) return false;
    library = handle; // Go libraries must remain loaded for the process lifetime.
    char* value = version();
    const bool valid = value && *value;
    release(value);
    return valid;
}
void RecordPacket(const void* buf, ssize_t count, bool outgoing) {
    if (count <= 0 || !buf) return;
    const auto family = *static_cast<const unsigned char*>(buf) >> 4;
    if (outgoing) {
        txBytes += count;
        if (family == 4) tx4Bytes += count;
        if (family == 6) tx6Bytes += count;
    } else {
        rxBytes += count;
        if (family == 4) rx4Bytes += count;
        if (family == 6) rx6Bytes += count;
    }
}
void RecordVector(const struct iovec* iov, int size, ssize_t count, bool outgoing) {
    for (int i = 0; i < size && count > 0; ++i) {
        if (iov[i].iov_len > 0) { RecordPacket(iov[i].iov_base, count, outgoing); return; }
    }
}
extern "C" ssize_t __wrap_read(int fd, void* buf, size_t size) {
    auto count = __real_read(fd, buf, size);
    if (fd == tunnelFd) RecordPacket(buf, count, true);
    return count;
}
extern "C" ssize_t __wrap_readv(int fd, const struct iovec* iov, int size) {
    auto count = __real_readv(fd, iov, size);
    if (fd == tunnelFd) RecordVector(iov, size, count, true);
    return count;
}
extern "C" ssize_t __wrap_write(int fd, const void* buf, size_t size) {
    auto count = __real_write(fd, buf, size);
    if (fd == tunnelFd) RecordPacket(buf, count, false);
    return count;
}
extern "C" ssize_t __wrap_writev(int fd, const struct iovec* iov, int size) {
    auto count = __real_writev(fd, iov, size);
    if (fd == tunnelFd) RecordVector(iov, size, count, false);
    return count;
}
void StopInner() {
    if (tunnel.joinable()) {
        { std::lock_guard<std::mutex> lock(readyMutex);
          if (ready && !finished) hev_socks5_tunnel_quit(); }
        tunnel.join();
    }
    if (library) stop();
}
}
// Hev's event pipe exists before this call, so stop cannot race its initialization.
extern "C" int __wrap_hev_socks5_tunnel_run(void) {
    { std::lock_guard<std::mutex> lock(readyMutex); ready = true; }
    readyCondition.notify_all();
    return __real_hev_socks5_tunnel_run();
}
namespace harmony_proxy {
const char* GetVersion() { return "Xray 26.7.28 / Hev 2.9.0"; }
bool IsAvailable() { std::lock_guard<std::mutex> lock(operation); return Load(); }
std::string BeginLatencyBatch(const std::string& id) {
    std::lock_guard<std::mutex> lock(operation);
    if (!Load()) return "core_unavailable";
    NetConn_NetHandle underlay{};
    NetConn_NetCapabilities caps{};
    if (OH_NetConn_GetDefaultNet(&underlay) != 0 || underlay.netId <= 0 ||
        OH_NetConn_GetNetCapabilities(&underlay, &caps) != 0) return "underlay_unavailable";
    for (int i = 0; i < caps.bearerTypesSize; ++i) {
        if (caps.bearerTypes[i] == NETCONN_BEARER_VPN) return "underlay_is_vpn";
    }
    // Test sockets are explicitly bound to this physical network by Go's
    // dialer controller. No system VPN or local SOCKS listener is created.
    char* result = beginLatency(id.c_str());
    std::string error = result ? result : "batch_failed";
    release(result);
    if (error.empty()) setNetwork(underlay.netId);
    return error;
}
std::string MeasureLatency(const std::string& config, const std::string& id) {
    // Never hold the lifecycle mutex across network I/O: cancellation must be
    // able to enter while up to three workers are waiting on their deadlines.
    { std::lock_guard<std::mutex> lock(operation);
      if (!library) return "{\"status\":\"failed\",\"latencyMs\":0}"; }
    char* result = measureLatency(config.c_str(), id.c_str());
    std::string output = result ? result : "{\"status\":\"failed\",\"latencyMs\":0}";
    release(result);
    return output;
}
std::string CancelLatencyBatch(const std::string& id, bool finish) {
    std::lock_guard<std::mutex> lock(operation);
    if (library) { if (finish) endLatency(id.c_str()); else cancelLatency(id.c_str()); }
    return "";
}
std::string Start(const std::string& config) {
    std::lock_guard<std::mutex> lock(operation);
    if (!Load()) return "error:core_unavailable";
    StopInner();
    NetConn_NetHandle underlay{};
    if (OH_NetConn_GetDefaultNet(&underlay) != 0 || underlay.netId <= 0) return "error:underlay_unavailable";
    NetConn_NetCapabilities caps{};
    if (OH_NetConn_GetNetCapabilities(&underlay, &caps) != 0) return "error:underlay_unavailable";
    for (int i = 0; i < caps.bearerTypesSize; ++i) {
        if (caps.bearerTypes[i] == NETCONN_BEARER_VPN) return "error:underlay_is_vpn";
    }
    setNetwork(underlay.netId);
    char* result = start(config.c_str());
    const bool failed = !result || *result;
    const std::string failure = result ? result : "core_start";
    release(result);
    if (failed) return "error:" + failure;
    char* ip = probe();
    std::string address = ip ? ip : "";
    release(ip);
    if (address.empty() || address.rfind("error:", 0) == 0) {
        StopInner(); return address.empty() ? "error:node_unreachable" : address;
    }
    return address;
}
std::string StartTunnel(int fd, const std::string& yaml) {
    std::lock_guard<std::mutex> lock(operation);
    if (fd < 0 || tunnel.joinable()) return "error:tunnel_state";
    const int owned = dup(fd);
    if (owned < 0) return "error:tunnel_fd";
    { std::lock_guard<std::mutex> state(readyMutex); ready = false; finished = false; }
    tunnelFd = owned; txBytes = 0; rxBytes = 0;
    tx4Bytes = 0; rx4Bytes = 0; tx6Bytes = 0; rx6Bytes = 0;
    tunnel = std::thread([owned, yaml] {
        hev_socks5_tunnel_main_from_str(reinterpret_cast<const unsigned char*>(yaml.data()), yaml.size(), owned);
        close(owned);
        tunnelFd = -1;
        { std::lock_guard<std::mutex> state(readyMutex); finished = true; }
        readyCondition.notify_all();
    });
    std::unique_lock<std::mutex> state(readyMutex);
    readyCondition.wait(state, [] { return ready || finished; });
    return finished ? "error:tunnel_init" : "";
}
void Stop() { std::lock_guard<std::mutex> lock(operation); StopInner(); }
std::string Stats() {
    std::lock_guard<std::mutex> state(readyMutex);
    return "{\"running\":" + std::string(ready && !finished ? "true" : "false") +
        ",\"tx\":" + std::to_string(txBytes.load()) + ",\"rx\":" + std::to_string(rxBytes.load()) +
        ",\"tx4\":" + std::to_string(tx4Bytes.load()) + ",\"rx4\":" + std::to_string(rx4Bytes.load()) +
        ",\"tx6\":" + std::to_string(tx6Bytes.load()) + ",\"rx6\":" + std::to_string(rx6Bytes.load()) + "}";
}
}
