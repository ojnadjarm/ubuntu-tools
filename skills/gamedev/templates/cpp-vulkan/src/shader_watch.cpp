#include "shader_watch.hpp"

#include "pipeline.hpp"

#include <sys/inotify.h>
#include <unistd.h>

#include <chrono>
#include <cstdio>
#include <exception>
#include <filesystem>
#include <set>
#include <stdexcept>

namespace {

/** Runs cmd through the shell, appending its stdout and stderr to log; true on exit status 0. */
bool run(const std::string& cmd, std::string& log) {
    FILE* pipe = popen((cmd + " 2>&1").c_str(), "r");
    if (!pipe) return false;
    char buf[512];
    while (std::fgets(buf, sizeof(buf), pipe)) log += buf;
    return pclose(pipe) == 0;
}

bool is_shader(const std::string& name) {
    const std::string ext = std::filesystem::path(name).extension().string();
    return ext == ".vert" || ext == ".frag" || ext == ".comp";
}

}  // namespace

ShaderWatch::ShaderWatch(VkDevice device) : device_(device), fd_(inotify_init1(IN_NONBLOCK | IN_CLOEXEC)) {
    if (fd_ < 0 || inotify_add_watch(fd_, GAME_SHADER_SRC_DIR, IN_CLOSE_WRITE | IN_MOVED_TO) < 0)
        throw std::runtime_error("inotify on " GAME_SHADER_SRC_DIR);
    std::printf("HOT watching %s\n", GAME_SHADER_SRC_DIR);
}

ShaderWatch::~ShaderWatch() { close(fd_); }

void ShaderWatch::poll() {
    alignas(inotify_event) char buf[4096];
    std::set<std::string> changed;
    for (ssize_t n; (n = read(fd_, buf, sizeof(buf))) > 0;) {
        for (char* p = buf; p < buf + n;) {
            const auto* event = reinterpret_cast<const inotify_event*>(p);
            if (event->len && is_shader(event->name)) changed.insert(event->name);
            p += sizeof(inotify_event) + event->len;
        }
    }
    for (const std::string& name : changed) reload(name);
}

void ShaderWatch::reload(const std::string& name) {
    const auto t0 = std::chrono::steady_clock::now();
    const std::string src = std::string(GAME_SHADER_SRC_DIR) + "/" + name;
    const std::string spv = std::string(GAME_SHADER_DIR) + "/" + name + ".spv";
    const std::string tmp = spv + ".hot";
    std::string log;
    if (!run(GAME_GLSLANG " -V --target-env vulkan1.3 -o '" + tmp + "' '" + src + "'", log) ||
        !run(GAME_SPIRV_VAL " --target-env vulkan1.3 '" + tmp + "'", log)) {
        std::remove(tmp.c_str());
        std::printf("HOT error %s (old pipeline kept)\n%s", name.c_str(), log.c_str());
        std::fflush(stdout);
        return;
    }
    std::filesystem::rename(tmp, spv);
    vkDeviceWaitIdle(device_);
    try {
        const int pipelines = reload_pipelines(name + ".spv");
        const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        std::printf("HOT reload %s pipelines=%d ms=%.1f\n", name.c_str(), pipelines, ms);
    } catch (const std::exception& e) {
        std::printf("HOT error %s: %s (old pipeline kept)\n", name.c_str(), e.what());
    }
    std::fflush(stdout);
}
