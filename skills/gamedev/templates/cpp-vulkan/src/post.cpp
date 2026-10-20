#include "post.hpp"

#include "pipeline.hpp"
#include "profiling.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace {

constexpr VkFormat kBloomFormat = VK_FORMAT_B10G11R11_UFLOAT_PACK32;
constexpr float kBloomMix = 0.04f;

void check(VkResult result, const char* what) {
    if (result != VK_SUCCESS) throw std::runtime_error(what);
}

/** Push constants of post.frag. */
struct PostPush {
    float exposure;
    float bloom_mix;
    float bloom_scale;
    uint32_t fxaa;
};

VkDescriptorSetLayout create_layout(VkDevice dev, VkShaderStageFlags stage, VkDescriptorType second) {
    const VkDescriptorSetLayoutBinding bindings[2] = {{0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, stage, nullptr},
                                                      {1, second, 1, stage, nullptr}};
    VkDescriptorSetLayoutCreateInfo info{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    info.bindingCount = 2;
    info.pBindings = bindings;
    VkDescriptorSetLayout layout;
    check(vkCreateDescriptorSetLayout(dev, &info, nullptr, &layout), "post set layout");
    return layout;
}

VkPipelineLayout create_pipeline_layout(VkDevice dev, VkDescriptorSetLayout set, VkShaderStageFlags stage,
                                        uint32_t push_size) {
    const VkPushConstantRange push{stage, 0, push_size};
    VkPipelineLayoutCreateInfo info{.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    info.setLayoutCount = 1;
    info.pSetLayouts = &set;
    info.pushConstantRangeCount = 1;
    info.pPushConstantRanges = &push;
    VkPipelineLayout layout;
    check(vkCreatePipelineLayout(dev, &info, nullptr, &layout), "post pipeline layout");
    return layout;
}

VkPipeline create_bloom_pipeline(VkDevice dev, VkPipelineLayout layout) {
    VkComputePipelineCreateInfo info{.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    info.stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                  .module = load_shader(dev, "bloom.comp.spv"), .pName = "main"};
    info.layout = layout;
    VkPipeline pipeline;
    const VkResult created = vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &info, nullptr, &pipeline);
    vkDestroyShaderModule(dev, info.stage.module, nullptr);
    check(created, "bloom pipeline");
    return pipeline;
}

/** Fullscreen triangle, no depth, one colour_format attachment; FXAA is a push-constant branch of post.frag. */
VkPipeline create_post_pipeline(VkDevice dev, VkPipelineLayout layout, VkFormat color_format) {
    VkShaderModule vert = load_shader(dev, "post.vert.spv");
    VkShaderModule frag = load_shader(dev, "post.frag.spv");
    const VkPipelineShaderStageCreateInfo stages[2] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT,
         .module = vert, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
         .module = frag, .pName = "main"},
    };
    VkPipelineVertexInputStateCreateInfo vertex_input{.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    VkPipelineInputAssemblyStateCreateInfo assembly{.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkPipelineViewportStateCreateInfo viewport{.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    viewport.viewportCount = 1;
    viewport.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo raster{.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    raster.polygonMode = VK_POLYGON_MODE_FILL;
    raster.cullMode = VK_CULL_MODE_NONE;
    raster.lineWidth = 1.0f;
    VkPipelineMultisampleStateCreateInfo multisample{.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo depth{.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    VkPipelineColorBlendAttachmentState blend_attachment{};
    blend_attachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT |
                                      VK_COLOR_COMPONENT_A_BIT;
    VkPipelineColorBlendStateCreateInfo blend{.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    blend.attachmentCount = 1;
    blend.pAttachments = &blend_attachment;
    const VkDynamicState dynamic_states[2] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic{.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dynamic.dynamicStateCount = 2;
    dynamic.pDynamicStates = dynamic_states;
    VkPipelineRenderingCreateInfo rendering{.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    rendering.colorAttachmentCount = 1;
    rendering.pColorAttachmentFormats = &color_format;

    VkGraphicsPipelineCreateInfo info{.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    info.pNext = &rendering;
    info.stageCount = 2;
    info.pStages = stages;
    info.pVertexInputState = &vertex_input;
    info.pInputAssemblyState = &assembly;
    info.pViewportState = &viewport;
    info.pRasterizationState = &raster;
    info.pMultisampleState = &multisample;
    info.pDepthStencilState = &depth;
    info.pColorBlendState = &blend;
    info.pDynamicState = &dynamic;
    info.layout = layout;
    VkPipeline pipeline;
    const VkResult created = vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE, 1, &info, nullptr, &pipeline);
    vkDestroyShaderModule(dev, vert, nullptr);
    vkDestroyShaderModule(dev, frag, nullptr);
    check(created, "post pipeline");
    return pipeline;
}

/** Compute writes of the last bloom pass made visible to the next pass and to the tonemap fragment shader. */
void bloom_barrier(VkCommandBuffer cmd) {
    VkMemoryBarrier2 barrier{.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2};
    barrier.srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
    barrier.srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT;
    barrier.dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
    barrier.dstAccessMask = VK_ACCESS_2_SHADER_SAMPLED_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_READ_BIT |
                            VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT;
    VkDependencyInfo dep{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    dep.memoryBarrierCount = 1;
    dep.pMemoryBarriers = &barrier;
    vkCmdPipelineBarrier2(cmd, &dep);
}

}  // namespace

PostChain::PostChain(GpuContext& gpu, uint32_t frames_in_flight)
    : gpu_(gpu),
      timer_(gpu, frames_in_flight),
      bloom_layout_(create_layout(gpu.device(), VK_SHADER_STAGE_COMPUTE_BIT, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE)),
      post_layout_(create_layout(gpu.device(), VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER)),
      bloom_pipeline_layout_(
          create_pipeline_layout(gpu.device(), bloom_layout_, VK_SHADER_STAGE_COMPUTE_BIT, sizeof(uint32_t))),
      post_pipeline_layout_(
          create_pipeline_layout(gpu.device(), post_layout_, VK_SHADER_STAGE_FRAGMENT_BIT, sizeof(PostPush))),
      bloom_pipeline_(create_bloom_pipeline(gpu.device(), bloom_pipeline_layout_)),
      post_pipeline_(create_post_pipeline(gpu.device(), post_pipeline_layout_, gpu.format())) {
    VkDevice dev = gpu_.device();
    VkSamplerCreateInfo sampler{.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    sampler.magFilter = VK_FILTER_LINEAR;
    sampler.minFilter = VK_FILTER_LINEAR;
    sampler.addressModeU = sampler.addressModeV = sampler.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sampler.maxLod = VK_LOD_CLAMP_NONE;
    check(vkCreateSampler(dev, &sampler, nullptr, &sampler_), "post sampler");

    const VkDescriptorPoolSize sizes[2] = {{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, kPasses + 2},
                                           {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, kPasses}};
    VkDescriptorPoolCreateInfo pool{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pool.maxSets = kPasses + 1;
    pool.poolSizeCount = 2;
    pool.pPoolSizes = sizes;
    check(vkCreateDescriptorPool(dev, &pool, nullptr, &pool_), "post descriptor pool");
    std::array<VkDescriptorSetLayout, kPasses> layouts;
    layouts.fill(bloom_layout_);
    VkDescriptorSetAllocateInfo alloc{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    alloc.descriptorPool = pool_;
    alloc.descriptorSetCount = kPasses;
    alloc.pSetLayouts = layouts.data();
    check(vkAllocateDescriptorSets(dev, &alloc, bloom_sets_.data()), "bloom sets");
    alloc.descriptorSetCount = 1;
    alloc.pSetLayouts = &post_layout_;
    check(vkAllocateDescriptorSets(dev, &alloc, &post_set_), "post set");
    add_reload_hook(this, {"bloom.comp.spv", "post.vert.spv", "post.frag.spv"}, [this] {
        VkDevice dev = gpu_.device();
        VkPipeline bloom = create_bloom_pipeline(dev, bloom_pipeline_layout_);
        VkPipeline post;
        try {
            post = create_post_pipeline(dev, post_pipeline_layout_, gpu_.format());
        } catch (...) {
            vkDestroyPipeline(dev, bloom, nullptr);
            throw;
        }
        vkDestroyPipeline(dev, bloom_pipeline_, nullptr);
        vkDestroyPipeline(dev, post_pipeline_, nullptr);
        bloom_pipeline_ = bloom;
        post_pipeline_ = post;
    });
}

PostChain::~PostChain() {
    remove_reload_hook(this);
    VkDevice dev = gpu_.device();
    destroy_images();
    vkDestroyDescriptorPool(dev, pool_, nullptr);
    vkDestroySampler(dev, sampler_, nullptr);
    vkDestroyPipeline(dev, post_pipeline_, nullptr);
    vkDestroyPipeline(dev, bloom_pipeline_, nullptr);
    vkDestroyPipelineLayout(dev, post_pipeline_layout_, nullptr);
    vkDestroyPipelineLayout(dev, bloom_pipeline_layout_, nullptr);
    vkDestroyDescriptorSetLayout(dev, post_layout_, nullptr);
    vkDestroyDescriptorSetLayout(dev, bloom_layout_, nullptr);
}

void PostChain::destroy_images() {
    for (VkImageView& v : levels_) {
        vkDestroyImageView(gpu_.device(), v, nullptr);
        v = VK_NULL_HANDLE;
    }
    if (bloom_.image) destroy_color_image(gpu_, bloom_);
}

void PostChain::set_exposure(float ev) { exposure_ = std::exp2(ev); }

void PostChain::resize(VkImageView hdr, VkExtent2D extent) {
    VkDevice dev = gpu_.device();
    destroy_images();
    extent_ = extent;
    for (uint32_t i = 0; i < kBloomLevels; i++)
        sizes_[i] = {std::max(1u, extent.width >> (i + 1)), std::max(1u, extent.height >> (i + 1))};
    bloom_ = create_color_image(gpu_, sizes_[0], kBloomFormat, VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
                                kBloomLevels);
    for (uint32_t i = 0; i < kBloomLevels; i++) {
        VkImageViewCreateInfo view{.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        view.image = bloom_.image;
        view.viewType = VK_IMAGE_VIEW_TYPE_2D;
        view.format = kBloomFormat;
        view.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, i, 1, 0, 1};
        check(vkCreateImageView(dev, &view, nullptr, &levels_[i]), "bloom level view");
    }

    // Passes 0..4 downsample hdr -> level 0 -> ... -> level 4; passes 5..7 upsample level 4 -> ... -> level 1.
    std::array<VkDescriptorImageInfo, 2 * kPasses + 2> images{};
    std::array<VkWriteDescriptorSet, 2 * kPasses + 2> writes{};
    const auto write = [&](uint32_t n, VkDescriptorSet set, uint32_t binding, VkDescriptorType type,
                           VkDescriptorImageInfo image) {
        images[n] = image;
        writes[n] = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = binding,
                     .descriptorCount = 1, .descriptorType = type, .pImageInfo = &images[n]};
    };
    for (uint32_t p = 0; p < kPasses; p++) {
        const bool up = p >= kBloomLevels;
        const uint32_t dst = up ? kPasses - p : p;
        const VkDescriptorImageInfo src = up       ? VkDescriptorImageInfo{sampler_, levels_[dst + 1], VK_IMAGE_LAYOUT_GENERAL}
                                          : p == 0 ? VkDescriptorImageInfo{sampler_, hdr, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL}
                                                   : VkDescriptorImageInfo{sampler_, levels_[p - 1], VK_IMAGE_LAYOUT_GENERAL};
        write(2 * p, bloom_sets_[p], 0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, src);
        write(2 * p + 1, bloom_sets_[p], 1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
              {VK_NULL_HANDLE, levels_[dst], VK_IMAGE_LAYOUT_GENERAL});
    }
    write(2 * kPasses, post_set_, 0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
          {sampler_, hdr, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL});
    write(2 * kPasses + 1, post_set_, 1, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
          {sampler_, bloom_.view, VK_IMAGE_LAYOUT_GENERAL});
    vkUpdateDescriptorSets(dev, static_cast<uint32_t>(writes.size()), writes.data(), 0, nullptr);
    init_bloom_layout();
}

/** Moves every bloom level to GENERAL once; frames then only order their accesses. */
void PostChain::init_bloom_layout() {
    VkCommandPoolCreateInfo pool_info{.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pool_info.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
    pool_info.queueFamilyIndex = gpu_.queue_family();
    VkCommandPool pool;
    check(vkCreateCommandPool(gpu_.device(), &pool_info, nullptr, &pool), "post command pool");
    VkCommandBufferAllocateInfo alloc{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    alloc.commandPool = pool;
    alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc.commandBufferCount = 1;
    VkCommandBuffer cmd;
    check(vkAllocateCommandBuffers(gpu_.device(), &alloc, &cmd), "post command buffer");
    VkCommandBufferBeginInfo begin{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    check(vkBeginCommandBuffer(cmd, &begin), "post begin");
    VkImageMemoryBarrier2 barrier{.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
    barrier.dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
    barrier.dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.image = bloom_.image;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, kBloomLevels, 0, 1};
    VkDependencyInfo dep{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    dep.imageMemoryBarrierCount = 1;
    dep.pImageMemoryBarriers = &barrier;
    vkCmdPipelineBarrier2(cmd, &dep);
    check(vkEndCommandBuffer(cmd), "post end");
    VkCommandBufferSubmitInfo cmd_info{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO};
    cmd_info.commandBuffer = cmd;
    VkSubmitInfo2 submit{.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2};
    submit.commandBufferInfoCount = 1;
    submit.pCommandBufferInfos = &cmd_info;
    check(vkQueueSubmit2(gpu_.queue(), 1, &submit, VK_NULL_HANDLE), "post submit");
    check(vkQueueWaitIdle(gpu_.queue()), "post wait");
    vkDestroyCommandPool(gpu_.device(), pool, nullptr);
}

void PostChain::record(VkCommandBuffer cmd, uint32_t slot, VkImageView target) {
    ZoneScopedN("post_chain");
    timer_.begin(cmd, slot, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT);
    // Last frame's bloom and tonemap reads finish before this frame's writes (write-after-read: execution only).
    VkMemoryBarrier2 after_reads{.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2};
    after_reads.srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
    after_reads.dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
    VkDependencyInfo dep{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    dep.memoryBarrierCount = 1;
    dep.pMemoryBarriers = &after_reads;
    vkCmdPipelineBarrier2(cmd, &dep);

    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, bloom_pipeline_);
    for (uint32_t p = 0; p < kPasses; p++) {
        const uint32_t mode = p == 0 ? 0u : p < kBloomLevels ? 1u : 2u;
        const VkExtent2D size = sizes_[mode == 2 ? kPasses - p : p];
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, bloom_pipeline_layout_, 0, 1, &bloom_sets_[p], 0,
                                nullptr);
        vkCmdPushConstants(cmd, bloom_pipeline_layout_, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(mode), &mode);
        vkCmdDispatch(cmd, (size.width + 7) / 8, (size.height + 7) / 8, 1);
        bloom_barrier(cmd);
    }

    draw(cmd, target);
    timer_.end(cmd, slot);
}

void PostChain::draw(VkCommandBuffer cmd, VkImageView target) {
    VkRenderingAttachmentInfo attachment{.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    attachment.imageView = target;
    attachment.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    attachment.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    VkRenderingInfo rendering{.sType = VK_STRUCTURE_TYPE_RENDERING_INFO};
    rendering.renderArea = {{0, 0}, extent_};
    rendering.layerCount = 1;
    rendering.colorAttachmentCount = 1;
    rendering.pColorAttachments = &attachment;
    vkCmdBeginRendering(cmd, &rendering);
    const VkViewport viewport{0, 0, float(extent_.width), float(extent_.height), 0, 1};
    const VkRect2D scissor{{0, 0}, extent_};
    vkCmdSetViewport(cmd, 0, 1, &viewport);
    vkCmdSetScissor(cmd, 0, 1, &scissor);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, post_pipeline_);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, post_pipeline_layout_, 0, 1, &post_set_, 0, nullptr);
    const PostPush push{exposure_, kBloomMix, 1.0f / kBloomLevels, fxaa_};
    vkCmdPushConstants(cmd, post_pipeline_layout_, VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(push), &push);
    vkCmdDraw(cmd, 3, 1, 0, 0);
    vkCmdEndRendering(cmd);
}
