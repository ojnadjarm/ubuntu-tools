#pragma once

#include "gpu_context.hpp"
#include "gpu_resources.hpp"
#include "gpu_timer.hpp"

#include <array>
#include <cstdint>
#include <optional>

/** HDR post chain: 5-level dual-filter bloom (compute, B10G11R11, from a 2x2 box of the HDR image), AgX + exposure and FXAA 3.11 in one pass into a swapchain image. */
class PostChain {
public:
    static constexpr uint32_t kBloomLevels = 5;

    PostChain(GpuContext& gpu, uint32_t frames_in_flight);
    ~PostChain();
    PostChain(const PostChain&) = delete;
    PostChain& operator=(const PostChain&) = delete;

    /** (Re)creates the bloom chain at half of extent and points the descriptors at hdr (SHADER_READ_ONLY_OPTIMAL). */
    void resize(VkImageView hdr, VkExtent2D extent);
    /** Records bloom and the tonemap pass into target (COLOR_ATTACHMENT_OPTIMAL before and after), timed in slot. */
    void record(VkCommandBuffer cmd, uint32_t slot, VkImageView target);
    std::optional<double> collect_ms(uint32_t slot) { return timer_.collect(slot); }
    void set_exposure(float ev);
    /** true: the tonemap pass runs FXAA on its tonemapped neighbours. */
    void set_fxaa(bool on) { fxaa_ = on; }

private:
    /** 5 downsamples, then upsamples into levels 3..1; post.frag adds level 0 to the upsampled level 1. */
    static constexpr uint32_t kPasses = 2 * kBloomLevels - 2;

    GpuContext& gpu_;
    GpuTimer timer_;
    VkSampler sampler_ = VK_NULL_HANDLE;
    VkDescriptorSetLayout bloom_layout_ = VK_NULL_HANDLE;
    VkDescriptorSetLayout post_layout_ = VK_NULL_HANDLE;
    VkPipelineLayout bloom_pipeline_layout_ = VK_NULL_HANDLE;
    VkPipelineLayout post_pipeline_layout_ = VK_NULL_HANDLE;
    VkPipeline bloom_pipeline_ = VK_NULL_HANDLE;
    VkPipeline post_pipeline_ = VK_NULL_HANDLE;
    VkDescriptorPool pool_ = VK_NULL_HANDLE;
    std::array<VkDescriptorSet, kPasses> bloom_sets_{};
    VkDescriptorSet post_set_ = VK_NULL_HANDLE;
    ColorImage bloom_;
    std::array<VkImageView, kBloomLevels> levels_{};
    std::array<VkExtent2D, kBloomLevels> sizes_{};
    VkExtent2D extent_{};
    float exposure_ = 1.0f;
    bool fxaa_ = true;

    void destroy_images();
    void init_bloom_layout();
    /** One fullscreen triangle of post.frag into target. */
    void draw(VkCommandBuffer cmd, VkImageView target);
};
