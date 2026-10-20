#include "texture.hpp"

#include "gpu_resources.hpp"

#include <ktx.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void check(VkResult result, const char* what) {
    if (result != VK_SUCCESS) throw std::runtime_error(what);
}

struct Encoding {
    ktx_transcode_fmt_e target;
    VkFormat unorm, srgb;
    const char* name;
};

bool samples_linear(const GpuContext& gpu, VkFormat format) {
    VkFormatProperties props;
    vkGetPhysicalDeviceFormatProperties(gpu.physical_device(), format, &props);
    return props.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT;
}

Encoding pick_encoding(const GpuContext& gpu) {
    const Encoding bc7{KTX_TTF_BC7_RGBA, VK_FORMAT_BC7_UNORM_BLOCK, VK_FORMAT_BC7_SRGB_BLOCK, "bc7"};
    const Encoding etc2{KTX_TTF_ETC2_RGBA, VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK, VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK, "etc2"};
    if (gpu.features().textureCompressionBC && samples_linear(gpu, bc7.srgb)) return bc7;
    if (gpu.features().textureCompressionETC2 && samples_linear(gpu, etc2.srgb)) return etc2;
    return {KTX_TTF_RGBA32, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_R8G8B8A8_SRGB, "rgba8"};
}

void barrier(VkCommandBuffer cmd, VkImage image, uint32_t levels, VkImageLayout from, VkImageLayout to,
             VkPipelineStageFlags2 src_stage, VkAccessFlags2 src_access, VkPipelineStageFlags2 dst_stage,
             VkAccessFlags2 dst_access) {
    VkImageMemoryBarrier2 b{.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
    b.srcStageMask = src_stage;
    b.srcAccessMask = src_access;
    b.dstStageMask = dst_stage;
    b.dstAccessMask = dst_access;
    b.oldLayout = from;
    b.newLayout = to;
    b.image = image;
    b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, levels, 0, 1};
    VkDependencyInfo dep{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    dep.imageMemoryBarrierCount = 1;
    dep.pImageMemoryBarriers = &b;
    vkCmdPipelineBarrier2(cmd, &dep);
}

/** Creates the image and copies each level from data at offsets[level] through one staging buffer. */
Texture upload(const GpuContext& gpu, VkFormat format, VkExtent2D extent, const void* data, VkDeviceSize size,
               const std::vector<VkDeviceSize>& offsets) {
    VkDevice dev = gpu.device();
    const auto levels = static_cast<uint32_t>(offsets.size());
    Texture t{.levels = levels};
    VkImageCreateInfo info{.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = format;
    info.extent = {extent.width, extent.height, 1};
    info.mipLevels = levels;
    info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    VmaAllocationCreateInfo alloc_info{};
    alloc_info.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
    check(vmaCreateImage(gpu.allocator(), &info, &alloc_info, &t.image, &t.allocation, nullptr), "texture image");

    Buffer staging = create_buffer(gpu, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, data, size);
    VkCommandPoolCreateInfo pool_info{.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pool_info.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
    pool_info.queueFamilyIndex = gpu.queue_family();
    VkCommandPool pool;
    check(vkCreateCommandPool(dev, &pool_info, nullptr, &pool), "upload pool");
    VkCommandBufferAllocateInfo alloc{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    alloc.commandPool = pool;
    alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc.commandBufferCount = 1;
    VkCommandBuffer cmd;
    check(vkAllocateCommandBuffers(dev, &alloc, &cmd), "upload cmd");
    VkCommandBufferBeginInfo begin{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    check(vkBeginCommandBuffer(cmd, &begin), "begin upload");
    barrier(cmd, t.image, levels, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            VK_PIPELINE_STAGE_2_NONE, 0, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT);
    std::vector<VkBufferImageCopy> regions(levels);
    for (uint32_t i = 0; i < levels; i++) {
        regions[i].bufferOffset = offsets[i];
        regions[i].imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, i, 0, 1};
        regions[i].imageExtent = {std::max(1u, extent.width >> i), std::max(1u, extent.height >> i), 1};
    }
    vkCmdCopyBufferToImage(cmd, staging.buffer, t.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, levels, regions.data());
    barrier(cmd, t.image, levels, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
            VK_ACCESS_2_SHADER_SAMPLED_READ_BIT);
    check(vkEndCommandBuffer(cmd), "end upload");
    VkCommandBufferSubmitInfo cmd_info{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO};
    cmd_info.commandBuffer = cmd;
    VkSubmitInfo2 submit{.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2};
    submit.commandBufferInfoCount = 1;
    submit.pCommandBufferInfos = &cmd_info;
    check(vkQueueSubmit2(gpu.queue(), 1, &submit, VK_NULL_HANDLE), "submit upload");
    check(vkQueueWaitIdle(gpu.queue()), "wait upload");
    vkDestroyCommandPool(dev, pool, nullptr);
    destroy_buffer(gpu, staging);

    VkImageViewCreateInfo view{.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    view.image = t.image;
    view.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view.format = format;
    view.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, levels, 0, 1};
    check(vkCreateImageView(dev, &view, nullptr, &t.view), "texture view");
    return t;
}

}  // namespace

Texture load_texture(const GpuContext& gpu, std::span<const uint8_t> ktx2, bool srgb, std::array<uint8_t, 4> fallback) {
    if (ktx2.empty()) {
        Texture t = upload(gpu, srgb ? VK_FORMAT_R8G8B8A8_SRGB : VK_FORMAT_R8G8B8A8_UNORM, {1, 1}, fallback.data(),
                           fallback.size(), {0});
        t.format = "fallback";
        return t;
    }
    ktxTexture2* raw = nullptr;
    KTX_error_code rc = ktxTexture2_CreateFromMemory(ktx2.data(), ktx2.size(), KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT, &raw);
    if (rc != KTX_SUCCESS) throw std::runtime_error(std::string("KTX2 load: ") + ktxErrorString(rc));
    std::unique_ptr<ktxTexture2, void (*)(ktxTexture2*)> tex(raw, [](ktxTexture2* t) { ktxTexture_Destroy(ktxTexture(t)); });
    VkFormat format = static_cast<VkFormat>(tex->vkFormat);
    const char* name = "native";
    if (ktxTexture2_NeedsTranscoding(tex.get())) {
        const Encoding enc = pick_encoding(gpu);
        rc = ktxTexture2_TranscodeBasis(tex.get(), enc.target, 0);
        if (rc != KTX_SUCCESS) throw std::runtime_error(std::string("KTX2 transcode: ") + ktxErrorString(rc));
        format = srgb ? enc.srgb : enc.unorm;
        name = enc.name;
    }
    std::vector<VkDeviceSize> offsets(tex->numLevels);
    for (uint32_t i = 0; i < tex->numLevels; i++) {
        ktx_size_t offset = 0;
        ktxTexture_GetImageOffset(ktxTexture(tex.get()), i, 0, 0, &offset);
        offsets[i] = offset;
    }
    Texture t = upload(gpu, format, {tex->baseWidth, tex->baseHeight}, ktxTexture_GetData(ktxTexture(tex.get())),
                       ktxTexture_GetDataSize(ktxTexture(tex.get())), offsets);
    t.format = name;
    return t;
}

void destroy_texture(const GpuContext& gpu, Texture& t) {
    vkDestroyImageView(gpu.device(), t.view, nullptr);
    vmaDestroyImage(gpu.allocator(), t.image, t.allocation);
    t = {};
}
