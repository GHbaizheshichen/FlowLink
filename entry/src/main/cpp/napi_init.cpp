#include "napi/native_api.h"
#include "proxy_core/proxy_core.h"
#include <string>
#include <memory>
namespace {
struct Work {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string input, second, output;
    int fd = -1, operation = 0;
};
std::string Read(napi_env env, napi_value value) {
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok || size > 65536) return "";
    std::string result(size + 1, '\0');
    napi_get_value_string_utf8(env, value, result.data(), result.size(), &size);
    result.resize(size); return result;
}
napi_value String(napi_env env, const std::string& text) {
    napi_value value; napi_create_string_utf8(env, text.c_str(), text.size(), &value); return value;
}
napi_value Version(napi_env env, napi_callback_info) { return String(env, harmony_proxy::GetVersion()); }
napi_value Available(napi_env env, napi_callback_info) {
    napi_value value; napi_get_boolean(env, harmony_proxy::IsAvailable(), &value); return value;
}
void Execute(napi_env, void* data) {
    auto* work = static_cast<Work*>(data);
    if (work->operation == 0) work->output = harmony_proxy::Start(work->input);
    else if (work->operation == 1) work->output = harmony_proxy::StartTunnel(work->fd, work->input);
    else if (work->operation == 3) work->output = harmony_proxy::Stats();
    else if (work->operation == 4) work->output = harmony_proxy::BeginLatencyBatch(work->input);
    else if (work->operation == 5) work->output = harmony_proxy::MeasureLatency(work->input, work->second);
    else if (work->operation == 6 || work->operation == 7)
        work->output = harmony_proxy::CancelLatencyBatch(work->input, work->operation == 7);
    else harmony_proxy::Stop();
}
void Complete(napi_env env, napi_status status, void* data) {
    std::unique_ptr<Work> work(static_cast<Work*>(data));
    if (status == napi_ok) napi_resolve_deferred(env, work->deferred, String(env, work->output));
    else napi_reject_deferred(env, work->deferred, String(env, "native_work_failed"));
    napi_delete_async_work(env, work->work);
}
napi_value Schedule(napi_env env, napi_callback_info info) {
    size_t count = 2; napi_value args[2]; void* operation;
    napi_get_cb_info(env, info, &count, args, nullptr, &operation);
    auto work = std::make_unique<Work>();
    work->operation = static_cast<int>(reinterpret_cast<intptr_t>(operation));
    if (work->operation != 1 && count >= 1) work->input = Read(env, args[0]);
    if (work->operation == 5 && count >= 2) work->second = Read(env, args[1]);
    if (work->operation == 1 && count >= 2) {
        napi_get_value_int32(env, args[0], &work->fd); work->input = Read(env, args[1]);
    }
    napi_value promise; napi_create_promise(env, &work->deferred, &promise);
    napi_create_async_work(env, nullptr, String(env, "HarmonyProxyCore"), Execute, Complete, work.get(), &work->work);
    napi_queue_async_work(env, work->work); work.release(); return promise;
}
napi_value Init(napi_env env, napi_value exports) {
    const napi_property_descriptor properties[] = {
        {"getVersion", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isAvailable", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, Schedule, nullptr, nullptr, nullptr, napi_default, reinterpret_cast<void*>(0)},
        {"startTunnel", nullptr, Schedule, nullptr, nullptr, nullptr, napi_default, reinterpret_cast<void*>(1)},
        {"stop", nullptr, Schedule, nullptr, nullptr, nullptr, napi_default, reinterpret_cast<void*>(2)},
        {"stats", nullptr, Schedule, nullptr, nullptr, nullptr, napi_default, reinterpret_cast<void*>(3)},
        {"beginLatencyBatch", nullptr, Schedule, nullptr, nullptr, nullptr, napi_default, reinterpret_cast<void*>(4)},
        {"measureLatency", nullptr, Schedule, nullptr, nullptr, nullptr, napi_default, reinterpret_cast<void*>(5)},
        {"cancelLatencyBatch", nullptr, Schedule, nullptr, nullptr, nullptr, napi_default, reinterpret_cast<void*>(6)},
        {"endLatencyBatch", nullptr, Schedule, nullptr, nullptr, nullptr, napi_default, reinterpret_cast<void*>(7)},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties); return exports;
}
napi_module module = {1, 0, nullptr, Init, "proxy_core", nullptr, {nullptr}};
}
extern "C" __attribute__((constructor)) void RegisterProxyCoreModule() { napi_module_register(&module); }
