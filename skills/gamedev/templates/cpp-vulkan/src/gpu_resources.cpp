#include "gpu_resources.hpp"

#include <cstring>
#include <stdexcept>

namespace {

void check(VkResult result, const char* what) {
    if (result != VK_SUCCESS) throw std::runtime_error(what);
}

}  // namespace

Buffer create_buffer(const GpuContext& gpu, VkBufferUsageFlags usage, const void* data, VkDeviceSize size) {
    Buffer b;
    VkBufferCreateInfo info{.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    info.size = size;
    info.usage = usage;
    VmaAllocationCreateInfo alloc{};
    alloc.flags = VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT | VMA_ALLOCATION_CREATE_MAPPED_BIT;
    alloc.usage = VMA_MEMORY_USAGE_AUTO;
    alloc.requiredFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    VmaAllocationInfo out;
    check(vmaCreateBuffer(gpu.allocator(), &info, &alloc, &b.buffer, &b.allocation, &out), "buffer");
    b.mapped = out.pMappedData;
    if (data) std::memcpy(b.mapped, data, size);
    return b;
}

void destroy_buffer(const GpuContext& gpu, Buffer& b) {
    vmaDestroyBuffer(gpu.allocator(), b.buffer, b.allocation);
    b = {};
}

DepthImage create_depth_image(const GpuContext& gpu, VkExtent2D extent, VkImageUsageFlags extra_usage) {
    DepthImage d;
    VkImageCreateInfo info{.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = DepthImage::kFormat;
    info.extent = {extent.width, extent.height, 1};
    info.mipLevels = 1;
    info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | extra_usage;
    VmaAllocationCreateInfo alloc{};
    alloc.flags = VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT;
    alloc.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
    check(vmaCreateImage(gpu.allocator(), &info, &alloc, &d.image, &d.allocation, nullptr), "depth image");

    VkImageViewCreateInfo view{.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    view.image = d.image;
    view.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view.format = DepthImage::kFormat;
    view.subresourceRange = {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1};
    check(vkCreateImageView(gpu.device(), &view, nullptr, &d.view), "depth view");
    return d;
}

void destroy_depth_image(const GpuContext& gpu, DepthImage& d) {
    vkDestroyImageView(gpu.device(), d.view, nullptr);
    vmaDestroyImage(gpu.allocator(), d.image, d.allocation);
    d = {};
}

ColorImage create_color_image(const GpuContext& gpu, VkExtent2D extent, VkFormat format, VkImageUsageFlags usage,
                              uint32_t levels) {
    ColorImage c;
    VkImageCreateInfo info{.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = format;
    info.extent = {extent.width, extent.height, 1};
    info.mipLevels = levels;
    info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = usage;
    VmaAllocationCreateInfo alloc{};
    alloc.flags = VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT;
    alloc.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
    check(vmaCreateImage(gpu.allocator(), &info, &alloc, &c.image, &c.allocation, nullptr), "colour image");

    VkImageViewCreateInfo view{.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    view.image = c.image;
    view.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view.format = format;
    view.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, levels, 0, 1};
    check(vkCreateImageView(gpu.device(), &view, nullptr, &c.view), "colour view");
    return c;
}

void destroy_color_image(const GpuContext& gpu, ColorImage& c) {
    vkDestroyImageView(gpu.device(), c.view, nullptr);
    vmaDestroyImage(gpu.allocator(), c.image, c.allocation);
    c = {};
}
