#pragma once

#include "gpu_context.hpp"

#include <glm/glm.hpp>

#include <functional>
#include <string>
#include <vector>

/** Loads GAME_SHADER_DIR/name (SPIR-V) into a shader module; throws when missing. */
VkShaderModule load_shader(VkDevice device, const char* name);

/** Registers owner's rebuild, which recreates its pipelines from the SPIR-V files in spv and keeps the old ones when it throws. */
void add_reload_hook(const void* owner, std::vector<std::string> spv, std::function<void()> rebuild);
void remove_reload_hook(const void* owner);
/** Runs every hook that loads spv (call with the device idle); returns how many ran, rethrows the first failure. */
int reload_pipelines(const std::string& spv);

/** Push constants of the mesh shaders (128 B, the guaranteed minimum). */
struct MeshPush {
    glm::mat4 mvp;
    glm::mat4 model;
};

/** The lit-mesh pipeline (material set 0, frame set 1, skinned: joint set 2) and the depth-only shadow pipeline (slope-scaled bias) on one layout, built through a VkPipelineCache kept on disk. */
class MeshPipeline {
public:
    /** skinned: skinned.vert for both pipelines, SkinVertex stream at binding 1. */
    MeshPipeline(const GpuContext& gpu, VkFormat color_format, VkFormat depth_format,
                 const std::vector<VkDescriptorSetLayout>& sets, bool skinned = false);
    ~MeshPipeline();
    MeshPipeline(const MeshPipeline&) = delete;
    MeshPipeline& operator=(const MeshPipeline&) = delete;

    VkPipeline pipeline() const { return pipeline_; }
    VkPipeline shadow_pipeline() const { return shadow_; }
    VkPipelineLayout layout() const { return layout_; }

private:
    void build();

    VkDevice device_;
    VkFormat color_format_;
    VkFormat depth_format_;
    bool skinned_;
    std::string cache_path_;
    VkPipelineCache cache_ = VK_NULL_HANDLE;
    VkPipelineLayout layout_ = VK_NULL_HANDLE;
    VkPipeline pipeline_ = VK_NULL_HANDLE;
    VkPipeline shadow_ = VK_NULL_HANDLE;
};
