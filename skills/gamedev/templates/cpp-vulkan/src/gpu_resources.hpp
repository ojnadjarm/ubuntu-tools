#pragma once

#include "gpu_context.hpp"

/** A persistently mapped buffer in host-visible, coherent memory. */
struct Buffer {
    VkBuffer buffer = VK_NULL_HANDLE;
    VmaAllocation allocation = VK_NULL_HANDLE;
    void* mapped = nullptr;
};

/** A depth attachment image with its view (also sampled when created with VK_IMAGE_USAGE_SAMPLED_BIT). */
struct DepthImage {
    static constexpr VkFormat kFormat = VK_FORMAT_D32_SFLOAT;
    VkImage image = VK_NULL_HANDLE;
    VmaAllocation allocation = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
};

/** A colour image with a view over all its mip levels. */
struct ColorImage {
    VkImage image = VK_NULL_HANDLE;
    VmaAllocation allocation = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
};

/** Creates a host-visible buffer; data may be null for a readback buffer. */
Buffer create_buffer(const GpuContext& gpu, VkBufferUsageFlags usage, const void* data, VkDeviceSize size);
void destroy_buffer(const GpuContext& gpu, Buffer& buffer);
DepthImage create_depth_image(const GpuContext& gpu, VkExtent2D extent, VkImageUsageFlags extra_usage = 0);
void destroy_depth_image(const GpuContext& gpu, DepthImage& depth);
ColorImage create_color_image(const GpuContext& gpu, VkExtent2D extent, VkFormat format, VkImageUsageFlags usage,
                              uint32_t levels = 1);
void destroy_color_image(const GpuContext& gpu, ColorImage& color);
