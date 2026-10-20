#pragma once

#include "animation.hpp"
#include "gpu_context.hpp"
#include "gpu_resources.hpp"
#include "pipeline.hpp"

#include <glm/glm.hpp>

#include <span>
#include <vector>

/** One animated character on the GPU: vertex, skin and index streams, a joint-matrix SSBO per frame slot (set 2), the skinned lit + shadow pipelines, and the model whose clips it samples. */
class SkinnedDraw {
public:
    SkinnedDraw(const GpuContext& gpu, SkinnedModel model, uint32_t slots, VkFormat color_format,
                VkFormat depth_format, VkDescriptorSetLayout material, VkDescriptorSetLayout frame);
    ~SkinnedDraw();
    SkinnedDraw(const SkinnedDraw&) = delete;
    SkinnedDraw& operator=(const SkinnedDraw&) = delete;

    /** Writes slot's joint matrices for the locomotion state (the slot's last submit has finished). */
    void set_pose(uint32_t slot, const Locomotion& state);
    /** Records the depth-only draws inside a shadow pass. */
    void record_shadow(VkCommandBuffer cmd, uint32_t slot, const glm::mat4& light, const glm::mat4& model);
    /** Records the lit draws inside the scene pass; materials[i] is the set of the model's material i. */
    void record_lit(VkCommandBuffer cmd, uint32_t slot, const glm::mat4& view_proj, const glm::mat4& model,
                    VkDescriptorSet frame, std::span<const VkDescriptorSet> materials);

private:
    void bind(VkCommandBuffer cmd, uint32_t slot, VkPipeline pipeline);

    const GpuContext& gpu_;
    SkinnedModel model_;
    VkDescriptorSetLayout joint_layout_;
    MeshPipeline pipeline_;
    VkDescriptorPool pool_ = VK_NULL_HANDLE;
    std::vector<Buffer> joints_;
    std::vector<VkDescriptorSet> sets_;
    Buffer mesh_;
    VkDeviceSize skin_offset_;
    VkDeviceSize index_offset_;
};
