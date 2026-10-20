#pragma once

#include "gpu_context.hpp"

#include <optional>
#include <vector>

/** Render passes timed per frame, in DONE-line order. */
enum class GpuPass : uint8_t { Shadow, Scene, Post, Skin, Count };
inline constexpr size_t kGpuPasses = static_cast<size_t>(GpuPass::Count);
/** DONE-line field of a pass's median GPU time, e.g. gpu_ms_p50_shadow. */
const char* gpu_pass_key(GpuPass pass);

/** GPU time per frame-in-flight slot and zone from two timestamp queries each, read back without stalling. */
class GpuTimer {
public:
    GpuTimer(const GpuContext& gpu, uint32_t slots, uint32_t zones = 1);
    ~GpuTimer();
    GpuTimer(const GpuTimer&) = delete;
    GpuTimer& operator=(const GpuTimer&) = delete;

    /** Zone 0's begin resets every zone of the slot (outside a render pass), so later zones may begin inside one. */
    void begin(VkCommandBuffer cmd, uint32_t slot, VkPipelineStageFlags2 stage = VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
               uint32_t zone = 0);
    void end(VkCommandBuffer cmd, uint32_t slot, uint32_t zone = 0);
    std::optional<double> collect(uint32_t slot, uint32_t zone = 0);

private:
    VkDevice device_;
    VkQueryPool pool_ = VK_NULL_HANDLE;
    double ns_per_tick_;
    uint64_t mask_;
    uint32_t zones_;
    std::vector<bool> pending_;
};
