#include "gpu_timer.hpp"

#include <stdexcept>

const char* gpu_pass_key(GpuPass pass) {
    static constexpr const char* kKeys[kGpuPasses] = {"gpu_ms_p50_shadow", "gpu_ms_p50_scene", "gpu_ms_p50_post",
                                                      "gpu_ms_p50_skin"};
    return kKeys[static_cast<size_t>(pass)];
}

GpuTimer::GpuTimer(const GpuContext& gpu, uint32_t slots, uint32_t zones)
    : device_(gpu.device()),
      ns_per_tick_(gpu.timestamp_period()),
      mask_(gpu.timestamp_bits() >= 64 ? ~0ull : (1ull << gpu.timestamp_bits()) - 1),
      zones_(zones),
      pending_(size_t{slots} * zones, false) {
    if (gpu.timestamp_bits() == 0) return;
    VkQueryPoolCreateInfo info{.sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO};
    info.queryType = VK_QUERY_TYPE_TIMESTAMP;
    info.queryCount = 2 * slots * zones;
    if (vkCreateQueryPool(device_, &info, nullptr, &pool_) != VK_SUCCESS) throw std::runtime_error("query pool");
}

GpuTimer::~GpuTimer() {
    if (pool_) vkDestroyQueryPool(device_, pool_, nullptr);
}

void GpuTimer::begin(VkCommandBuffer cmd, uint32_t slot, VkPipelineStageFlags2 stage, uint32_t zone) {
    if (!pool_) return;
    const uint32_t i = slot * zones_ + zone;
    if (zone == 0) vkCmdResetQueryPool(cmd, pool_, 2 * i, 2 * zones_);
    vkCmdWriteTimestamp2(cmd, stage, pool_, 2 * i);
}

void GpuTimer::end(VkCommandBuffer cmd, uint32_t slot, uint32_t zone) {
    if (!pool_) return;
    const uint32_t i = slot * zones_ + zone;
    vkCmdWriteTimestamp2(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, pool_, 2 * i + 1);
    pending_[i] = true;
}

std::optional<double> GpuTimer::collect(uint32_t slot, uint32_t zone) {
    const uint32_t i = slot * zones_ + zone;
    if (!pool_ || !pending_[i]) return std::nullopt;
    uint64_t r[4] = {};  // value, availability for each of the two queries
    VkResult res = vkGetQueryPoolResults(device_, pool_, 2 * i, 2, sizeof(r), r, 2 * sizeof(uint64_t),
                                         VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT);
    if (res != VK_SUCCESS || !r[1] || !r[3]) return std::nullopt;
    pending_[i] = false;
    return static_cast<double>((r[2] - r[0]) & mask_) * ns_per_tick_ * 1e-6;
}
