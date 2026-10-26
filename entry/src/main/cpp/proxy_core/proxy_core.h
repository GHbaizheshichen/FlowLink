#pragma once
#include <string>
namespace harmony_proxy {
const char* GetVersion();
bool IsAvailable();
std::string Start(const std::string& config);
std::string StartTunnel(int fd, const std::string& yaml);
std::string Stats();
void Stop();
std::string BeginLatencyBatch(const std::string& id);
std::string MeasureLatency(const std::string& config, const std::string& id);
std::string CancelLatencyBatch(const std::string& id, bool finish);
}
