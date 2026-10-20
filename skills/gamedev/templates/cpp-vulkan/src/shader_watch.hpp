#pragma once

#include <volk.h>

#include <string>

/** Dev-build shader hot reload: inotify on GAME_SHADER_SRC_DIR, glslang + spirv-val into GAME_SHADER_DIR, then the pipelines loading the changed file are rebuilt after vkDeviceWaitIdle. */
class ShaderWatch {
public:
    explicit ShaderWatch(VkDevice device);
    ~ShaderWatch();
    ShaderWatch(const ShaderWatch&) = delete;
    ShaderWatch& operator=(const ShaderWatch&) = delete;

    /** Reloads the shaders saved since the last call; a compile or pipeline error is printed and the old pipeline kept. */
    void poll();

private:
    void reload(const std::string& name);

    VkDevice device_;
    int fd_ = -1;
};
