#pragma once

#include "gpu_context.hpp"
#include "gpu_resources.hpp"

#include <cstdint>
#include <optional>
#include <string>

/** Image-based lighting from an equirectangular .hdr: SH9 irradiance, a GGX-prefiltered cube and a split-sum BRDF LUT, baked by compute at load and cached as KTX2 next to the .hdr. */
class Ibl {
public:
    static constexpr uint32_t kMips = 5;
    static constexpr uint32_t kCubeSize = 128;
    static constexpr uint32_t kLutSize = 128;

    /** hdr empty or missing: one black texel each, enabled() false. */
    Ibl(GpuContext& gpu, const std::string& hdr);
    ~Ibl();
    Ibl(const Ibl&) = delete;
    Ibl& operator=(const Ibl&) = delete;

    bool enabled() const { return enabled_; }
    VkImageView prefiltered() const { return cube_view_; }
    VkImageView brdf_lut() const { return lut_.view; }
    /** std140 block of 9 vec4 SH coefficients (diffuse radiance per unit albedo). */
    VkBuffer sh() const { return sh_.buffer; }
    VkSampler sampler() const { return sampler_; }
    /** GPU milliseconds of the last bake (none on a cache hit or when disabled). */
    std::optional<double> bake_ms() const { return bake_ms_; }

private:
    void create_targets(uint32_t cube_size, uint32_t mips, uint32_t lut_size);
    /** Bakes from hdr and writes hdr.ibl.ktx2 (cube, hash, SH9) and hdr.lut.ktx2 (LUT, hash). */
    void bake(const std::string& hdr, uint64_t hash);
    /** Uploads both cache files when their hash matches. */
    bool load_cache(const std::string& hdr, uint64_t hash);
    void clear_placeholders();

    GpuContext& gpu_;
    bool enabled_ = false;
    VkImage cube_ = VK_NULL_HANDLE;
    VmaAllocation cube_alloc_ = VK_NULL_HANDLE;
    VkImageView cube_view_ = VK_NULL_HANDLE;
    ColorImage lut_;
    Buffer sh_;
    VkSampler sampler_ = VK_NULL_HANDLE;
    std::optional<double> bake_ms_;
};
