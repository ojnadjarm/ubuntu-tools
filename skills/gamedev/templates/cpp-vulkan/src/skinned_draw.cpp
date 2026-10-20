#include "skinned_draw.hpp"

#include <cstddef>
#include <cstring>
#include <stdexcept>
#include <utility>

namespace {

void check(VkResult result, const char* what) {
    if (result != VK_SUCCESS) throw std::runtime_error(what);
}

/** Set 2: the joint matrices as a vertex-stage storage buffer. */
VkDescriptorSetLayout create_joint_layout(VkDevice dev) {
    const VkDescriptorSetLayoutBinding binding{0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT, nullptr};
    VkDescriptorSetLayoutCreateInfo info{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    info.bindingCount = 1;
    info.pBindings = &binding;
    VkDescriptorSetLayout layout;
    check(vkCreateDescriptorSetLayout(dev, &info, nullptr, &layout), "joint set layout");
    return layout;
}

}  // namespace

SkinnedDraw::SkinnedDraw(const GpuContext& gpu, SkinnedModel model, uint32_t slots, VkFormat color_format,
                         VkFormat depth_format, VkDescriptorSetLayout material, VkDescriptorSetLayout frame)
    : gpu_(gpu),
      model_(std::move(model)),
      joint_layout_(create_joint_layout(gpu.device())),
      pipeline_(gpu, color_format, depth_format, {material, frame, joint_layout_}, true),
      skin_offset_(model_.mesh.vertices.size() * sizeof(Vertex)),
      index_offset_(skin_offset_ + model_.mesh.skin.size() * sizeof(SkinVertex)) {
    const size_t index_bytes = model_.mesh.indices.size() * sizeof(uint32_t);
    std::vector<std::byte> bytes(index_offset_ + index_bytes);
    std::memcpy(bytes.data(), model_.mesh.vertices.data(), skin_offset_);
    std::memcpy(bytes.data() + skin_offset_, model_.mesh.skin.data(), index_offset_ - skin_offset_);
    std::memcpy(bytes.data() + index_offset_, model_.mesh.indices.data(), index_bytes);
    mesh_ = create_buffer(gpu_, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT, bytes.data(),
                          bytes.size());

    VkDevice dev = gpu_.device();
    const VkDescriptorPoolSize size{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, slots};
    VkDescriptorPoolCreateInfo pool{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pool.maxSets = slots;
    pool.poolSizeCount = 1;
    pool.pPoolSizes = &size;
    check(vkCreateDescriptorPool(dev, &pool, nullptr, &pool_), "joint descriptor pool");
    const VkDeviceSize joint_bytes = model_.joint_nodes.size() * sizeof(glm::mat4);
    for (uint32_t s = 0; s < slots; s++) {
        joints_.push_back(create_buffer(gpu_, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, nullptr, joint_bytes));
        VkDescriptorSetAllocateInfo alloc{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
        alloc.descriptorPool = pool_;
        alloc.descriptorSetCount = 1;
        alloc.pSetLayouts = &joint_layout_;
        VkDescriptorSet set;
        check(vkAllocateDescriptorSets(dev, &alloc, &set), "joint set");
        const VkDescriptorBufferInfo ssbo{joints_.back().buffer, 0, joint_bytes};
        const VkWriteDescriptorSet write{.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 0,
                                         .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                         .pBufferInfo = &ssbo};
        vkUpdateDescriptorSets(dev, 1, &write, 0, nullptr);
        sets_.push_back(set);
    }
}

SkinnedDraw::~SkinnedDraw() {
    VkDevice dev = gpu_.device();
    for (Buffer& b : joints_) destroy_buffer(gpu_, b);
    destroy_buffer(gpu_, mesh_);
    vkDestroyDescriptorPool(dev, pool_, nullptr);
    vkDestroyDescriptorSetLayout(dev, joint_layout_, nullptr);
}

void SkinnedDraw::set_pose(uint32_t slot, const Locomotion& state) {
    const std::vector<glm::mat4> joints = sample_pose(model_, state);
    std::memcpy(joints_[slot].mapped, joints.data(), joints.size() * sizeof(glm::mat4));
}

void SkinnedDraw::bind(VkCommandBuffer cmd, uint32_t slot, VkPipeline pipeline) {
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_.layout(), 2, 1, &sets_[slot], 0, nullptr);
    const VkBuffer buffers[2] = {mesh_.buffer, mesh_.buffer};
    const VkDeviceSize offsets[2] = {0, skin_offset_};
    vkCmdBindVertexBuffers(cmd, 0, 2, buffers, offsets);
    vkCmdBindIndexBuffer(cmd, mesh_.buffer, index_offset_, VK_INDEX_TYPE_UINT32);
}

void SkinnedDraw::record_shadow(VkCommandBuffer cmd, uint32_t slot, const glm::mat4& light, const glm::mat4& model) {
    bind(cmd, slot, pipeline_.shadow_pipeline());
    const MeshPush push{light * model, model};
    vkCmdPushConstants(cmd, pipeline_.layout(), VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(push), &push);
    for (const DrawData& d : model_.mesh.lods[0]) vkCmdDrawIndexed(cmd, d.index_count, 1, d.first_index, 0, 0);
}

void SkinnedDraw::record_lit(VkCommandBuffer cmd, uint32_t slot, const glm::mat4& view_proj, const glm::mat4& model,
                             VkDescriptorSet frame, std::span<const VkDescriptorSet> materials) {
    bind(cmd, slot, pipeline_.pipeline());
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_.layout(), 1, 1, &frame, 0, nullptr);
    const MeshPush push{view_proj * model, model};
    vkCmdPushConstants(cmd, pipeline_.layout(), VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(push), &push);
    for (const DrawData& d : model_.mesh.lods[0]) {
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_.layout(), 0, 1, &materials[d.material], 0,
                                nullptr);
        vkCmdDrawIndexed(cmd, d.index_count, 1, d.first_index, 0, 0);
    }
}
