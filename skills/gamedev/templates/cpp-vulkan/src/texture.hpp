#pragma once

#include "gpu_context.hpp"

#include <array>
#include <cstdint>
#include <span>

/** A sampled 2D image with its full mip chain; format names the GPU encoding (bc7, etc2, rgba8, native, fallback). */
struct Texture {
    VkImage image = VK_NULL_HANDLE;
    VmaAllocation allocation = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    const char* format = "";
    uint32_t levels = 0;
};

/** Transcodes KTX2 bytes to BC7, else ETC2, else RGBA8 and uploads every level; one texel of fallback when bytes is empty. */
Texture load_texture(const GpuContext& gpu, std::span<const uint8_t> ktx2, bool srgb, std::array<uint8_t, 4> fallback);
void destroy_texture(const GpuContext& gpu, Texture& texture);
