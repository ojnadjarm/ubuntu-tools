#include "renderer.hpp"

#include "profiling.hpp"

#include <SDL3/SDL.h>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <utility>

namespace {

void check(VkResult result, const char* what) {
    if (result != VK_SUCCESS) throw std::runtime_error(what);
}

void transition(VkCommandBuffer cmd, VkImage image, VkImageLayout from, VkImageLayout to,
                VkPipelineStageFlags2 src_stage, VkAccessFlags2 src_access,
                VkPipelineStageFlags2 dst_stage, VkAccessFlags2 dst_access,
                VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT) {
    VkImageMemoryBarrier2 barrier{.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
    barrier.srcStageMask = src_stage;
    barrier.srcAccessMask = src_access;
    barrier.dstStageMask = dst_stage;
    barrier.dstAccessMask = dst_access;
    barrier.oldLayout = from;
    barrier.newLayout = to;
    barrier.image = image;
    barrier.subresourceRange = {aspect, 0, 1, 0, 1};
    VkDependencyInfo dep{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    dep.imageMemoryBarrierCount = 1;
    dep.pImageMemoryBarriers = &barrier;
    vkCmdPipelineBarrier2(cmd, &dep);
}

const glm::vec3 kEye(0.0f, 0.8f, 2.6f);
const glm::vec3 kLightDir = glm::normalize(glm::vec3(0.4f, 0.8f, 0.5f));
constexpr uint32_t kShadowSize = 2048;
constexpr VkFormat kHdrFormat = VK_FORMAT_R16G16B16A16_SFLOAT;
constexpr VkImageUsageFlags kHdrUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
constexpr float kGroundHalf = 4.0f;
constexpr uint32_t kGroundVertices = 4;
constexpr float kCharacterHeight = 0.9f;  // the player capsule
constexpr float kIblStrength = 1.0f;

/** std140 block of mesh.frag binding 3. */
struct MaterialBlock {
    glm::vec4 base_color_factor;
    glm::vec4 params;
    glm::vec4 eye;
};

/** std140 block of mesh.frag set 1 binding 1. */
struct FrameBlock {
    glm::mat4 light_view_proj;
    glm::vec4 light_dir;
};

/** Set 1: the shadow map as a compare sampler (binding 0), the frame block (1), the prefiltered cube (2), the BRDF LUT (3) and SH9 (4). */
VkDescriptorSetLayout create_frame_layout(VkDevice dev) {
    const VkDescriptorSetLayoutBinding bindings[5] = {
        {0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr},
        {2, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr},
        {3, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr},
        {4, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo info{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    info.bindingCount = 5;
    info.pBindings = bindings;
    VkDescriptorSetLayout layout;
    check(vkCreateDescriptorSetLayout(dev, &info, nullptr, &layout), "frame set layout");
    return layout;
}

/** An upward-facing square of half size kGroundHalf at height y. */
std::array<Vertex, kGroundVertices> ground_quad(float y) {
    constexpr float corners[kGroundVertices][2] = {{-1, -1}, {-1, 1}, {1, 1}, {1, -1}};
    std::array<Vertex, kGroundVertices> v{};
    for (uint32_t i = 0; i < kGroundVertices; i++) {
        const float x = corners[i][0] * kGroundHalf, z = corners[i][1] * kGroundHalf;
        v[i] = {{x, y, z}, {0.0f, 1.0f, 0.0f}, {x, z}, {1.0f, 0.0f, 0.0f, 1.0f}};
    }
    return v;
}

/** Set 0: base colour, normal and ORM samplers (bindings 0-2) and the material block (binding 3). */
VkDescriptorSetLayout create_material_layout(VkDevice dev) {
    VkDescriptorSetLayoutBinding bindings[4];
    for (uint32_t i = 0; i < 4; i++) {
        bindings[i] = {i, i < 3 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1,
                       VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    }
    VkDescriptorSetLayoutCreateInfo info{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    info.bindingCount = 4;
    info.pBindings = bindings;
    VkDescriptorSetLayout layout;
    check(vkCreateDescriptorSetLayout(dev, &info, nullptr, &layout), "descriptor set layout");
    return layout;
}

/** LOD n+1 replaces LOD n below this screen size (bounding-sphere diameter over screen height). */
constexpr std::array<float, 2> kLodScreenSize = {0.6f, 0.35f};
constexpr float kLodHysteresis = 0.1f;

/** True when the AABB lo..hi lies wholly outside one clip plane of mvp (Vulkan clip space, depth 0..w). */
bool outside_frustum(const glm::mat4& mvp, glm::vec3 lo, glm::vec3 hi) {
    std::array<glm::vec4, 8> c;
    for (uint32_t i = 0; i < 8; i++)
        c[i] = mvp * glm::vec4(i & 1 ? hi.x : lo.x, i & 2 ? hi.y : lo.y, i & 4 ? hi.z : lo.z, 1.0f);
    const auto all = [&c](auto out) { return std::all_of(c.begin(), c.end(), out); };
    return all([](glm::vec4 p) { return p.x < -p.w; }) || all([](glm::vec4 p) { return p.x > p.w; }) ||
           all([](glm::vec4 p) { return p.y < -p.w; }) || all([](glm::vec4 p) { return p.y > p.w; }) ||
           all([](glm::vec4 p) { return p.z < 0.0f; }) || all([](glm::vec4 p) { return p.z > p.w; });
}

/** Eye position of a perspective view-projection: the point clip x, y and w all map to zero. */
glm::vec3 eye_of(const glm::mat4& vp) {
    const glm::mat3 rows = glm::transpose(glm::mat3(glm::vec3(vp[0][0], vp[1][0], vp[2][0]),
                                                    glm::vec3(vp[0][1], vp[1][1], vp[2][1]),
                                                    glm::vec3(vp[0][3], vp[1][3], vp[2][3])));
    return glm::inverse(rows) * -glm::vec3(vp[3][0], vp[3][1], vp[3][3]);
}

float max_scale(const glm::mat4& model) {
    return std::max({glm::length(glm::vec3(model[0])), glm::length(glm::vec3(model[1])),
                     glm::length(glm::vec3(model[2]))});
}

/** Screen-height fraction covered by the instance's bounding sphere (radius at the model origin); huge when the eye is inside. */
float screen_size(const glm::mat4& view_proj, glm::vec3 eye, const glm::mat4& model, float radius) {
    const float r = radius * max_scale(model);
    const float distance = glm::length(glm::vec3(model[3]) - eye);
    const float focal = glm::length(glm::vec3(view_proj[0][1], view_proj[1][1], view_proj[2][1]));
    return distance > r ? r * focal / distance : 1e30f;
}

/** LOD for a screen size: a fresh pick from thresholds, else the current LOD moves only past the hysteresis band. */
int pick_lod(float size, int current, int count) {
    int lod = current;
    if (lod < 0 || lod >= count) {
        lod = 0;
        while (lod + 1 < count && size < kLodScreenSize[lod]) lod++;
        return lod;
    }
    while (lod + 1 < count && size < kLodScreenSize[lod] * (1.0f - kLodHysteresis)) lod++;
    while (lod > 0 && size > kLodScreenSize[lod - 1] * (1.0f + kLodHysteresis)) lod--;
    return lod;
}

uint64_t now_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

/** Timer zone 0 is the whole frame; a zone per pass follows (post's stays unused: it has its own timer). */
constexpr uint32_t kTimerZones = 1 + kGpuPasses;
constexpr uint32_t zone_of(GpuPass pass) { return 1 + static_cast<uint32_t>(pass); }

}  // namespace

Renderer::Renderer(GpuContext& gpu, const SceneData& scene, std::optional<SkinnedModel> character,
                   const std::string& environment)
    : gpu_(gpu),
      timer_(gpu, kFramesInFlight, kTimerZones),
      set_layout_(create_material_layout(gpu.device())),
      frame_layout_(create_frame_layout(gpu.device())),
      pipeline_(gpu, kHdrFormat, DepthImage::kFormat, {set_layout_, frame_layout_}),
      depth_(create_depth_image(gpu, gpu.extent())),
      hdr_(create_color_image(gpu, gpu.extent(), kHdrFormat, kHdrUsage)),
      post_(gpu, kFramesInFlight),
      ibl_(gpu, environment),
      shadow_map_(create_depth_image(gpu, {kShadowSize, kShadowSize}, VK_IMAGE_USAGE_SAMPLED_BIT)),
      index_offset_((scene.vertices.size() + kGroundVertices) * sizeof(Vertex)),
      lods_(scene.lods),
      radius_(scene.radius) {
    if (lods_.size() > kLodScreenSize.size() + 1) lods_.resize(kLodScreenSize.size() + 1);
    lift_ = -lowest_y(lods_[0]);
    const auto base = static_cast<uint32_t>(scene.vertices.size());
    const std::array<uint32_t, 6> ground_indices = {base, base + 1, base + 2, base, base + 2, base + 3};
    ground_ = {.first_index = static_cast<uint32_t>(scene.indices.size()), .index_count = 6,
               .material = static_cast<uint32_t>(scene.materials.size()), .transform = glm::mat4(1.0f),
               .lo = {-kGroundHalf, 0.0f, -kGroundHalf}, .hi = {kGroundHalf, 0.0f, kGroundHalf}};
    const std::array<Vertex, kGroundVertices> ground = ground_quad(0.0f);
    const size_t scene_vertex_bytes = scene.vertices.size() * sizeof(Vertex);
    const size_t scene_index_bytes = scene.indices.size() * sizeof(uint32_t);
    std::vector<std::byte> bytes(index_offset_ + scene_index_bytes + sizeof(ground_indices));
    std::memcpy(bytes.data(), scene.vertices.data(), scene_vertex_bytes);
    std::memcpy(bytes.data() + scene_vertex_bytes, ground.data(), sizeof(ground));
    std::memcpy(bytes.data() + index_offset_, scene.indices.data(), scene_index_bytes);
    std::memcpy(bytes.data() + index_offset_ + scene_index_bytes, ground_indices.data(), sizeof(ground_indices));
    mesh_ = create_buffer(gpu_, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT, bytes.data(),
                          bytes.size());
    std::vector<MaterialData> materials = scene.materials;
    materials.push_back({.base_color_factor = {0.5f, 0.5f, 0.5f, 1.0f}, .roughness = 0.8f});
    const size_t first_character_material = materials.size();
    if (character) {
        materials.insert(materials.end(), character->mesh.materials.begin(), character->mesh.materials.end());
        const glm::vec3 lo = character->lo, hi = character->hi;
        character_fit_ = glm::scale(glm::mat4(1.0f), glm::vec3(kCharacterHeight / (hi.y - lo.y))) *
                           glm::translate(glm::mat4(1.0f), {-0.5f * (lo.x + hi.x), -lo.y, -0.5f * (lo.z + hi.z)});
        skinned_.emplace(gpu, std::move(*character), kFramesInFlight, kHdrFormat, DepthImage::kFormat, set_layout_,
                         frame_layout_);
    }
    create_materials(materials, first_character_material);
    for (size_t i = first_character_material; i < materials_.size(); i++) character_sets_.push_back(materials_[i].set);
    VkDevice dev = gpu_.device();
    for (Frame& f : frames_) {
        VkCommandPoolCreateInfo pool_info{.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
        pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        pool_info.queueFamilyIndex = gpu_.queue_family();
        check(vkCreateCommandPool(dev, &pool_info, nullptr, &f.pool), "command pool");

        VkCommandBufferAllocateInfo alloc{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        alloc.commandPool = f.pool;
        alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        alloc.commandBufferCount = 1;
        check(vkAllocateCommandBuffers(dev, &alloc, &f.cmd), "command buffer");

        VkFenceCreateInfo fence_info{.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
        fence_info.flags = VK_FENCE_CREATE_SIGNALED_BIT;
        check(vkCreateFence(dev, &fence_info, nullptr, &f.in_flight), "fence");

        VkSemaphoreCreateInfo sem_info{.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        check(vkCreateSemaphore(dev, &sem_info, nullptr, &f.image_acquired), "semaphore");
    }
    create_frame_sets();
    create_present_semaphores();
    post_.resize(hdr_.view, gpu_.extent());
}

Renderer::~Renderer() {
    VkDevice dev = gpu_.device();
    vkDeviceWaitIdle(dev);
    destroy_present_semaphores();
    destroy_buffer(gpu_, mesh_);
    vkDestroyDescriptorPool(dev, descriptor_pool_, nullptr);
    vkDestroyDescriptorSetLayout(dev, set_layout_, nullptr);
    vkDestroyDescriptorSetLayout(dev, frame_layout_, nullptr);
    vkDestroySampler(dev, sampler_, nullptr);
    vkDestroySampler(dev, shadow_sampler_, nullptr);
    destroy_depth_image(gpu_, shadow_map_);
    for (Material& m : materials_) {
        destroy_buffer(gpu_, m.block);
        for (Texture& t : m.textures)
            if (t.image) destroy_texture(gpu_, t);
    }
    for (Texture& t : fallbacks_) destroy_texture(gpu_, t);
    destroy_depth_image(gpu_, depth_);
    destroy_color_image(gpu_, hdr_);
    for (Frame& f : frames_) {
        destroy_buffer(gpu_, f.block);
        vkDestroySemaphore(dev, f.image_acquired, nullptr);
        vkDestroyFence(dev, f.in_flight, nullptr);
        vkDestroyCommandPool(dev, f.pool, nullptr);
    }
}

void Renderer::create_materials(const std::vector<MaterialData>& materials, size_t first_character_material) {
    VkDevice dev = gpu_.device();
    fallbacks_[0] = load_texture(gpu_, {}, true, {255, 255, 255, 255});
    fallbacks_[1] = load_texture(gpu_, {}, false, {128, 128, 255, 255});
    fallbacks_[2] = load_texture(gpu_, {}, false, {255, 255, 255, 255});

    VkSamplerCreateInfo sampler{.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    sampler.magFilter = VK_FILTER_LINEAR;
    sampler.minFilter = VK_FILTER_LINEAR;
    sampler.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    sampler.addressModeU = sampler.addressModeV = sampler.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
    sampler.anisotropyEnable = gpu_.features().samplerAnisotropy;
    sampler.maxAnisotropy = std::min(16.0f, gpu_.max_anisotropy());
    sampler.maxLod = VK_LOD_CLAMP_NONE;
    check(vkCreateSampler(dev, &sampler, nullptr, &sampler_), "sampler");

    const auto count = static_cast<uint32_t>(materials.size());
    VkDescriptorPoolSize sizes[2] = {{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 3 * count + 3 * kFramesInFlight},
                                     {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, count + 2 * kFramesInFlight}};
    VkDescriptorPoolCreateInfo pool{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pool.maxSets = count + kFramesInFlight;
    pool.poolSizeCount = 2;
    pool.pPoolSizes = sizes;
    check(vkCreateDescriptorPool(dev, &pool, nullptr, &descriptor_pool_), "descriptor pool");

    materials_.resize(count);
    for (uint32_t n = 0; n < count; n++) {
        const MaterialData& m = materials[n];
        Material& out = materials_[n];
        const std::array<const std::vector<uint8_t>*, 3> maps = {&m.base_color, &m.normal, &m.orm};
        std::array<const Texture*, 3> used{};
        for (uint32_t i = 0; i < 3; i++) {
            if (!maps[i]->empty()) out.textures[i] = load_texture(gpu_, *maps[i], i == 0, {});
            used[i] = out.textures[i].image ? &out.textures[i] : &fallbacks_[i];
        }
        std::printf("%s base_color=%s:%u normal=%s:%u orm=%s:%u\n",
                    n < first_character_material ? "MATERIAL" : "SKIN material", used[0]->format, used[0]->levels,
                    used[1]->format, used[1]->levels, used[2]->format, used[2]->levels);

        const MaterialBlock block{glm::make_vec4(m.base_color_factor),
                                  {m.metallic, m.roughness, m.normal_scale, m.occlusion_strength}, glm::vec4(kEye, 1.0f)};
        out.block = create_buffer(gpu_, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, &block, sizeof(block));

        VkDescriptorSetAllocateInfo alloc{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
        alloc.descriptorPool = descriptor_pool_;
        alloc.descriptorSetCount = 1;
        alloc.pSetLayouts = &set_layout_;
        check(vkAllocateDescriptorSets(dev, &alloc, &out.set), "descriptor set");

        VkDescriptorImageInfo images[3];
        VkWriteDescriptorSet writes[4];
        for (uint32_t i = 0; i < 3; i++) {
            images[i] = {sampler_, used[i]->view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
            writes[i] = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = out.set, .dstBinding = i,
                         .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                         .pImageInfo = &images[i]};
        }
        const VkDescriptorBufferInfo ubo{out.block.buffer, 0, sizeof(MaterialBlock)};
        writes[3] = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = out.set, .dstBinding = 3,
                     .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pBufferInfo = &ubo};
        vkUpdateDescriptorSets(dev, 4, writes, 0, nullptr);
    }
}

void Renderer::create_frame_sets() {
    VkDevice dev = gpu_.device();
    VkSamplerCreateInfo sampler{.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    sampler.magFilter = VK_FILTER_LINEAR;
    sampler.minFilter = VK_FILTER_LINEAR;
    sampler.addressModeU = sampler.addressModeV = sampler.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER;
    sampler.borderColor = VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE;
    sampler.compareEnable = VK_TRUE;
    sampler.compareOp = VK_COMPARE_OP_LESS_OR_EQUAL;
    check(vkCreateSampler(dev, &sampler, nullptr, &shadow_sampler_), "shadow sampler");

    for (Frame& f : frames_) {
        f.block = create_buffer(gpu_, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, nullptr, sizeof(FrameBlock));
        VkDescriptorSetAllocateInfo alloc{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
        alloc.descriptorPool = descriptor_pool_;
        alloc.descriptorSetCount = 1;
        alloc.pSetLayouts = &frame_layout_;
        check(vkAllocateDescriptorSets(dev, &alloc, &f.set), "frame set");
        const VkDescriptorImageInfo image{shadow_sampler_, shadow_map_.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        const VkDescriptorBufferInfo ubo{f.block.buffer, 0, sizeof(FrameBlock)};
        const VkDescriptorImageInfo cube{ibl_.sampler(), ibl_.prefiltered(), VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        const VkDescriptorImageInfo lut{ibl_.sampler(), ibl_.brdf_lut(), VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        const VkDescriptorBufferInfo sh{ibl_.sh(), 0, VK_WHOLE_SIZE};
        const VkWriteDescriptorSet writes[5] = {
            {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = f.set, .dstBinding = 0, .descriptorCount = 1,
             .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &image},
            {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = f.set, .dstBinding = 1, .descriptorCount = 1,
             .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pBufferInfo = &ubo},
            {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = f.set, .dstBinding = 2, .descriptorCount = 1,
             .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &cube},
            {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = f.set, .dstBinding = 3, .descriptorCount = 1,
             .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &lut},
            {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = f.set, .dstBinding = 4, .descriptorCount = 1,
             .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pBufferInfo = &sh}};
        vkUpdateDescriptorSets(dev, 5, writes, 0, nullptr);
    }
}

void Renderer::set_character(glm::vec3 feet, float yaw, const Locomotion& state, bool visible) {
    character_model_ = glm::translate(glm::mat4(1.0f), feet) *
                       glm::rotate(glm::mat4(1.0f), yaw, glm::vec3(0.0f, 1.0f, 0.0f)) * character_fit_;
    locomotion_ = state;
    character_visible_ = visible;
}

/** Light view-projection: an orthographic box along kLightDir around every instance's bounding sphere and the ground. */
glm::mat4 Renderer::fit_light(const std::vector<glm::mat4>& models) const {
    const glm::mat4 view = glm::lookAt(kLightDir, glm::vec3(0.0f), glm::vec3(0.0f, 1.0f, 0.0f));
    glm::vec3 lo(1e30f), hi(-1e30f);
    const auto add = [&](glm::vec3 p, float r) {
        const glm::vec3 c(view * glm::vec4(p, 1.0f));
        lo = glm::min(lo, c - r);
        hi = glm::max(hi, c + r);
    };
    for (const glm::mat4& m : models) add(glm::vec3(m[3]), radius_ * max_scale(m));
    if (skinned_) add(glm::vec3(character_model_[3]) + glm::vec3(0.0f, 0.5f * kCharacterHeight, 0.0f), kCharacterHeight);
    add(ground_.lo, 0.0f);
    add(ground_.hi, 0.0f);
    add({ground_.lo.x, ground_.lo.y, ground_.hi.z}, 0.0f);
    add({ground_.hi.x, ground_.lo.y, ground_.lo.z}, 0.0f);
    // Bottom and top swapped: y down in the framebuffer, as the camera's flipped projection.
    return glm::orthoRH_ZO(lo.x, hi.x, hi.y, lo.y, -hi.z, -lo.z) * view;
}

/** Records one draw unless its AABB lies outside view_proj; binds its material set when bound is non-null (lit pass). */
bool Renderer::draw(VkCommandBuffer cmd, const glm::mat4& view_proj, const glm::mat4& model, const DrawData& d,
                    VkDescriptorSet* bound) {
    MeshPush push{.mvp = {}, .model = model * d.transform};
    push.mvp = view_proj * push.model;
    if (outside_frustum(push.mvp, d.lo, d.hi)) return false;
    const VkDescriptorSet set = materials_[d.material].set;
    if (bound && set != *bound) {
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_.layout(), 0, 1, &set, 0, nullptr);
        *bound = set;
    }
    vkCmdPushConstants(cmd, pipeline_.layout(), VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(push), &push);
    vkCmdDrawIndexed(cmd, d.index_count, 1, d.first_index, 0, 0);
    return true;
}

/** Draws one LOD of the scene; the lit pass (bound non-null) counts draws and culls in stats_. */
void Renderer::draw_instance(VkCommandBuffer cmd, const glm::mat4& view_proj, const glm::mat4& model, int lod,
                             VkDescriptorSet* bound) {
    for (const DrawData& d : lods_[lod]) {
        const bool drawn = draw(cmd, view_proj, model, d, bound);
        if (bound) (drawn ? stats_.draws : stats_.culled)++;
    }
}

void Renderer::record_shadow_pass(VkCommandBuffer cmd, const glm::mat4& light, const std::vector<glm::mat4>& models) {
    ZoneScopedN("shadow_pass");
    constexpr VkPipelineStageFlags2 depth_stages =
        VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT;
    // From the last frame's layout, not UNDEFINED: ANV re-initializes the depth aux surface on UNDEFINED (~0.05 ms at 2048²).
    transition(cmd, shadow_map_.image, shadow_layout_, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
               VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, 0, depth_stages,
               VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
               VK_IMAGE_ASPECT_DEPTH_BIT);
    VkRenderingAttachmentInfo depth{.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    depth.imageView = shadow_map_.view;
    depth.imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL;
    depth.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    depth.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    depth.clearValue.depthStencil = {1.0f, 0};
    VkRenderingInfo rendering{.sType = VK_STRUCTURE_TYPE_RENDERING_INFO};
    rendering.renderArea = {{0, 0}, {kShadowSize, kShadowSize}};
    rendering.layerCount = 1;
    rendering.pDepthAttachment = &depth;
    vkCmdBeginRendering(cmd, &rendering);
    const VkViewport viewport{0, 0, float(kShadowSize), float(kShadowSize), 0, 1};
    const VkRect2D scissor{{0, 0}, {kShadowSize, kShadowSize}};
    vkCmdSetViewport(cmd, 0, 1, &viewport);
    vkCmdSetScissor(cmd, 0, 1, &scissor);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_.shadow_pipeline());
    VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &mesh_.buffer, &offset);
    vkCmdBindIndexBuffer(cmd, mesh_.buffer, index_offset_, VK_INDEX_TYPE_UINT32);
    if (shadows_)
        for (size_t i = 0; i < models.size(); i++) draw_instance(cmd, light, models[i], instance_lods_[i], nullptr);
    if (shadows_ && skinned_) skinned_->record_shadow(cmd, frame_, light, character_model_);
    vkCmdEndRendering(cmd);
    transition(cmd, shadow_map_.image, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
               VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT, VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
               VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, VK_ACCESS_2_SHADER_SAMPLED_READ_BIT, VK_IMAGE_ASPECT_DEPTH_BIT);
    shadow_layout_ = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
}

void Renderer::draw_frame(const VkClearColorValue& color, float seconds) {
    VkDevice dev = gpu_.device();
    Frame& f = frames_[frame_];
    uint64_t t0 = now_ns();
    {
        ZoneScopedN("wait_fence");
        check(vkWaitForFences(dev, 1, &f.in_flight, VK_TRUE, UINT64_MAX), "wait fence");
    }
    gpu_ms_ = timer_.collect(frame_);
    for (GpuPass pass : {GpuPass::Shadow, GpuPass::Scene, GpuPass::Skin})
        pass_ms_[static_cast<size_t>(pass)] = timer_.collect(frame_, zone_of(pass));
    pass_ms_[static_cast<size_t>(GpuPass::Post)] = post_.collect_ms(frame_);

    uint32_t image_index = 0;
    {
        ZoneScopedN("acquire");
        VkResult acquired = vkAcquireNextImageKHR(dev, gpu_.swapchain(), UINT64_MAX, f.image_acquired,
                                                  VK_NULL_HANDLE, &image_index);
        blocked_ns_ = now_ns() - t0;
        if (acquired == VK_ERROR_OUT_OF_DATE_KHR) {
            recreate_swapchain();
            return;
        }
        if (acquired != VK_SUCCESS && acquired != VK_SUBOPTIMAL_KHR) throw std::runtime_error("acquire");
    }
    check(vkResetFences(dev, 1, &f.in_flight), "reset fence");

    check(vkResetCommandBuffer(f.cmd, 0), "reset cmd");
    record(f.cmd, image_index, color, seconds);

    VkSemaphoreSubmitInfo wait{.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO};
    wait.semaphore = f.image_acquired;
    wait.stageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSemaphoreSubmitInfo signal{.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO};
    signal.semaphore = render_done_[image_index];
    signal.stageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    VkCommandBufferSubmitInfo cmd_info{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO};
    cmd_info.commandBuffer = f.cmd;
    VkSubmitInfo2 submit{.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2};
    submit.waitSemaphoreInfoCount = 1;
    submit.pWaitSemaphoreInfos = &wait;
    submit.commandBufferInfoCount = 1;
    submit.pCommandBufferInfos = &cmd_info;
    submit.signalSemaphoreInfoCount = 1;
    submit.pSignalSemaphoreInfos = &signal;
    {
        ZoneScopedN("submit");
        check(vkQueueSubmit2(gpu_.queue(), 1, &submit, f.in_flight), "submit");
    }
    if (capture_buffer_.buffer) save_capture(f.in_flight);

    VkSwapchainKHR swapchain = gpu_.swapchain();
    VkPresentInfoKHR present{.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    present.waitSemaphoreCount = 1;
    present.pWaitSemaphores = &render_done_[image_index];
    present.swapchainCount = 1;
    present.pSwapchains = &swapchain;
    present.pImageIndices = &image_index;
    VkResult presented;
    {
        ZoneScopedN("present");
        t0 = now_ns();
        presented = vkQueuePresentKHR(gpu_.queue(), &present);
        blocked_ns_ += now_ns() - t0;
    }
    if (presented == VK_ERROR_OUT_OF_DATE_KHR || presented == VK_SUBOPTIMAL_KHR) {
        recreate_swapchain();
    } else {
        check(presented, "present");
    }
    frame_ = (frame_ + 1) % kFramesInFlight;
}

void Renderer::record(VkCommandBuffer cmd, uint32_t image_index, const VkClearColorValue& color, float seconds) {
    ZoneScopedN("record");
    VkCommandBufferBeginInfo begin{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    check(vkBeginCommandBuffer(cmd, &begin), "begin cmd");
    timer_.begin(cmd, frame_);

    const VkExtent2D extent = gpu_.extent();
    glm::mat4 proj = glm::perspectiveRH_ZO(glm::radians(45.0f), float(extent.width) / float(extent.height), 0.1f, 10.0f);
    proj[1][1] *= -1.0f;
    const glm::mat4 view_proj =
        view_proj_.value_or(proj * glm::lookAt(kEye, glm::vec3(0.0f), glm::vec3(0.0f, 1.0f, 0.0f)));
    std::vector<glm::mat4> models{glm::rotate(glm::translate(glm::mat4(1.0f), glm::vec3(0.0f, lift_, 0.0f)), 0.5f * seconds,
                                               glm::vec3(0.0f, 1.0f, 0.0f))};
    models.insert(models.end(), props_.begin(), props_.end());
    stats_ = {};
    instance_lods_.resize(models.size(), -1);
    const glm::vec3 eye = eye_of(view_proj);
    for (size_t i = 0; i < models.size(); i++) {
        instance_lods_[i] = pick_lod(screen_size(view_proj, eye, models[i], radius_), instance_lods_[i],
                                     static_cast<int>(lods_.size()));
        stats_.lods[instance_lods_[i]]++;
    }
    const glm::mat4 light = fit_light(models);
    const Frame& f = frames_[frame_];
    const FrameBlock block{light, glm::vec4(kLightDir, ibl_.enabled() ? kIblStrength : 0.0f)};
    std::memcpy(f.block.mapped, &block, sizeof(block));
    if (skinned_) skinned_->set_pose(frame_, locomotion_);
    timer_.begin(cmd, frame_, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zone_of(GpuPass::Shadow));
    record_shadow_pass(cmd, light, models);
    timer_.end(cmd, frame_, zone_of(GpuPass::Shadow));

    timer_.begin(cmd, frame_, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zone_of(GpuPass::Scene));
    // The previous frame's bloom and tonemap reads of the HDR target finish before the scene overwrites it.
    transition(cmd, hdr_.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
               VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, 0,
               VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    constexpr VkPipelineStageFlags2 depth_stages =
        VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT;
    transition(cmd, depth_.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, depth_stages,
               VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT, depth_stages,
               VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
               VK_IMAGE_ASPECT_DEPTH_BIT);

    VkRenderingAttachmentInfo attachment{.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    attachment.imageView = hdr_.view;
    attachment.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    attachment.clearValue.color = color;
    VkRenderingInfo rendering{.sType = VK_STRUCTURE_TYPE_RENDERING_INFO};
    rendering.renderArea = {{0, 0}, gpu_.extent()};
    rendering.layerCount = 1;
    rendering.colorAttachmentCount = 1;
    rendering.pColorAttachments = &attachment;
    VkRenderingAttachmentInfo depth{.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    depth.imageView = depth_.view;
    depth.imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL;
    depth.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    depth.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    depth.clearValue.depthStencil = {1.0f, 0};
    rendering.pDepthAttachment = &depth;
    vkCmdBeginRendering(cmd, &rendering);

    VkViewport viewport{0, 0, float(extent.width), float(extent.height), 0, 1};
    VkRect2D scissor{{0, 0}, extent};
    vkCmdSetViewport(cmd, 0, 1, &viewport);
    vkCmdSetScissor(cmd, 0, 1, &scissor);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_.pipeline());
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_.layout(), 1, 1, &f.set, 0, nullptr);
    VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &mesh_.buffer, &offset);
    vkCmdBindIndexBuffer(cmd, mesh_.buffer, index_offset_, VK_INDEX_TYPE_UINT32);
    VkDescriptorSet bound = VK_NULL_HANDLE;
    for (size_t i = 0; i < models.size(); i++) draw_instance(cmd, view_proj, models[i], instance_lods_[i], &bound);
    draw(cmd, view_proj, glm::mat4(1.0f), ground_, &bound);
    if (skinned_ && character_visible_) {
        timer_.begin(cmd, frame_, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, zone_of(GpuPass::Skin));
        skinned_->record_lit(cmd, frame_, view_proj, character_model_, f.set, character_sets_);
        timer_.end(cmd, frame_, zone_of(GpuPass::Skin));
    }
    // Draw calls go here.
    vkCmdEndRendering(cmd);

    transition(cmd, hdr_.image, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
               VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
               VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
               VK_ACCESS_2_SHADER_SAMPLED_READ_BIT);
    timer_.end(cmd, frame_, zone_of(GpuPass::Scene));
    VkImage image = gpu_.images()[image_index];
    transition(cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
               VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0,
               VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    post_.record(cmd, frame_, gpu_.image_views()[image_index]);

    if (!capture_path_.empty()) {
        record_capture(cmd, image);
    } else {
        transition(cmd, image, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                   VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                   VK_PIPELINE_STAGE_2_NONE, 0);
    }
    timer_.end(cmd, frame_);
    check(vkEndCommandBuffer(cmd), "end cmd");
}

void Renderer::record_capture(VkCommandBuffer cmd, VkImage image) {
    const VkExtent2D extent = gpu_.extent();
    capture_buffer_ = create_buffer(gpu_, VK_BUFFER_USAGE_TRANSFER_DST_BIT, nullptr,
                                    VkDeviceSize{extent.width} * extent.height * 4);
    transition(cmd, image, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
               VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
               VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT);
    VkBufferImageCopy region{};
    region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    region.imageExtent = {extent.width, extent.height, 1};
    vkCmdCopyImageToBuffer(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, capture_buffer_.buffer, 1, &region);
    transition(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
               VK_PIPELINE_STAGE_2_COPY_BIT, 0, VK_PIPELINE_STAGE_2_NONE, 0);
    VkMemoryBarrier2 to_host{.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2};
    to_host.srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT;
    to_host.srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT;
    to_host.dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT;
    to_host.dstAccessMask = VK_ACCESS_2_HOST_READ_BIT;
    VkDependencyInfo dep{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    dep.memoryBarrierCount = 1;
    dep.pMemoryBarriers = &to_host;
    vkCmdPipelineBarrier2(cmd, &dep);
}

void Renderer::save_capture(VkFence done) {
    VkDevice dev = gpu_.device();
    check(vkWaitForFences(dev, 1, &done, VK_TRUE, UINT64_MAX), "capture fence");
    const VkExtent2D extent = gpu_.extent();
    const bool bgra = gpu_.format() == VK_FORMAT_B8G8R8A8_UNORM || gpu_.format() == VK_FORMAT_B8G8R8A8_SRGB;
    SDL_Surface* surface =
        SDL_CreateSurfaceFrom(static_cast<int>(extent.width), static_cast<int>(extent.height),
                              bgra ? SDL_PIXELFORMAT_BGRX32 : SDL_PIXELFORMAT_RGBX32, capture_buffer_.mapped,
                              static_cast<int>(extent.width * 4));
    const bool saved = surface && SDL_SavePNG(surface, capture_path_.c_str());
    SDL_DestroySurface(surface);
    destroy_buffer(gpu_, capture_buffer_);
    if (!saved) throw std::runtime_error("capture " + capture_path_ + ": " + SDL_GetError());
    std::printf("CAPTURE path=%s extent=%ux%u format=%d\n", capture_path_.c_str(), extent.width, extent.height,
                gpu_.format());
    capture_path_.clear();
}

void Renderer::create_present_semaphores() {
    render_done_.resize(gpu_.images().size());
    VkSemaphoreCreateInfo sem_info{.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    for (VkSemaphore& s : render_done_) check(vkCreateSemaphore(gpu_.device(), &sem_info, nullptr, &s), "semaphore");
}

void Renderer::destroy_present_semaphores() {
    for (VkSemaphore s : render_done_) vkDestroySemaphore(gpu_.device(), s, nullptr);
    render_done_.clear();
}

void Renderer::recreate_swapchain() {
    if (!gpu_.recreate_swapchain()) return;
    destroy_present_semaphores();
    create_present_semaphores();
    destroy_depth_image(gpu_, depth_);
    depth_ = create_depth_image(gpu_, gpu_.extent());
    destroy_color_image(gpu_, hdr_);
    hdr_ = create_color_image(gpu_, gpu_.extent(), kHdrFormat, kHdrUsage);
    post_.resize(hdr_.view, gpu_.extent());
}
