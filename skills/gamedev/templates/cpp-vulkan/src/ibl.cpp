#include "ibl.hpp"

#include "gpu_timer.hpp"
#include "pipeline.hpp"

#include <glm/gtc/packing.hpp>
#include <ktx.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <vector>

namespace {

constexpr VkFormat kFormat = VK_FORMAT_R16G16B16A16_SFLOAT;
constexpr uint32_t kTexelBytes = 8;
constexpr uint32_t kShBytes = 9 * 16;
constexpr std::array<float, 36> kNoSh{};
constexpr const char* kHashKey = "ibl.hash";
constexpr const char* kShKey = "ibl.sh9";

void check(VkResult result, const char* what) {
    if (result != VK_SUCCESS) throw std::runtime_error(what);
}

std::vector<uint8_t> read_file(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return {};
    return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}

uint64_t fnv1a(const std::vector<uint8_t>& bytes, uint64_t h = 14695981039346656037ull) {
    for (uint8_t b : bytes) h = (h ^ b) * 1099511628211ull;
    return h;
}

/** Radiance RGBE (flat or new-style RLE scanlines, -Y H +X W) to linear RGBA floats. */
std::vector<float> decode_hdr(const std::vector<uint8_t>& in, uint32_t& w, uint32_t& h) {
    size_t i = 0;
    const auto line = [&] {
        std::string s;
        while (i < in.size() && in[i] != '\n') s += static_cast<char>(in[i++]);
        i++;
        return s;
    };
    if (line().rfind("#?", 0) != 0) throw std::runtime_error("hdr: not a Radiance file");
    while (i < in.size() && !line().empty()) {
    }
    if (std::sscanf(line().c_str(), "-Y %u +X %u", &h, &w) != 2 || w == 0 || h == 0)
        throw std::runtime_error("hdr: only -Y H +X W layouts");
    std::vector<uint8_t> rgbe(size_t{w} * h * 4);
    std::vector<uint8_t> row(size_t{w} * 4);
    for (uint32_t y = 0; y < h; y++) {
        uint8_t* out = &rgbe[size_t{y} * w * 4];
        if (i + 4 <= in.size() && in[i] == 2 && in[i + 1] == 2 && w >= 8 && w < 32768) {
            i += 4;
            for (uint32_t c = 0; c < 4; c++) {
                for (uint32_t x = 0; x < w && i < in.size();) {
                    uint32_t n = in[i++];
                    const bool run = n > 128;
                    if (run) n -= 128;
                    for (uint32_t k = 0; k < n && x < w && i < in.size(); k++) row[x++] = in[run ? i : i++];
                    if (run) i++;
                }
                for (uint32_t x = 0; x < w; x++) out[x * 4 + c] = row[x];
            }
        } else {
            if (i + size_t{w} * 4 > in.size()) throw std::runtime_error("hdr: truncated");
            std::memcpy(out, &in[i], size_t{w} * 4);
            i += size_t{w} * 4;
        }
    }
    std::vector<float> rgba(size_t{w} * h * 4);
    for (size_t p = 0; p < size_t{w} * h; p++) {
        const float f = rgbe[p * 4 + 3] ? std::ldexp(1.0f, rgbe[p * 4 + 3] - 136) : 0.0f;
        for (int c = 0; c < 3; c++) rgba[p * 4 + c] = rgbe[p * 4 + c] * f;
        rgba[p * 4 + 3] = 1.0f;
    }
    return rgba;
}

/** Box-filtered mip chain of an RGBA float image as half floats, level after level; offsets per level. */
std::vector<uint16_t> half_mips(std::vector<float> level, uint32_t w, uint32_t h, std::vector<VkDeviceSize>& offsets) {
    std::vector<uint16_t> out;
    while (true) {
        offsets.push_back(out.size() * sizeof(uint16_t));
        for (float v : level) out.push_back(static_cast<uint16_t>(glm::packHalf1x16(v)));
        if (w == 1 && h == 1) return out;
        const uint32_t nw = std::max(1u, w / 2), nh = std::max(1u, h / 2);
        std::vector<float> next(size_t{nw} * nh * 4, 0.0f);
        for (uint32_t y = 0; y < nh; y++)
            for (uint32_t x = 0; x < nw; x++)
                for (uint32_t d = 0; d < 4; d++) {
                    const uint32_t sx = std::min(2 * x + (d & 1), w - 1), sy = std::min(2 * y + (d >> 1), h - 1);
                    for (int c = 0; c < 4; c++) next[(size_t{y} * nw + x) * 4 + c] += 0.25f * level[(size_t{sy} * w + sx) * 4 + c];
                }
        level = std::move(next);
        w = nw;
        h = nh;
    }
}

/** A one-time command buffer submitted and waited on. */
struct OneShot {
    const GpuContext& gpu;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkCommandBuffer cmd = VK_NULL_HANDLE;

    explicit OneShot(const GpuContext& g) : gpu(g) {
        VkCommandPoolCreateInfo pool_info{.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
        pool_info.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
        pool_info.queueFamilyIndex = gpu.queue_family();
        check(vkCreateCommandPool(gpu.device(), &pool_info, nullptr, &pool), "ibl pool");
        VkCommandBufferAllocateInfo alloc{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        alloc.commandPool = pool;
        alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        alloc.commandBufferCount = 1;
        check(vkAllocateCommandBuffers(gpu.device(), &alloc, &cmd), "ibl cmd");
        VkCommandBufferBeginInfo begin{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        check(vkBeginCommandBuffer(cmd, &begin), "ibl begin");
    }
    ~OneShot() { vkDestroyCommandPool(gpu.device(), pool, nullptr); }
    OneShot(const OneShot&) = delete;
    OneShot& operator=(const OneShot&) = delete;

    void submit_and_wait() {
        check(vkEndCommandBuffer(cmd), "ibl end");
        VkCommandBufferSubmitInfo cmd_info{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO};
        cmd_info.commandBuffer = cmd;
        VkSubmitInfo2 submit{.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2};
        submit.commandBufferInfoCount = 1;
        submit.pCommandBufferInfos = &cmd_info;
        check(vkQueueSubmit2(gpu.queue(), 1, &submit, VK_NULL_HANDLE), "ibl submit");
        check(vkQueueWaitIdle(gpu.queue()), "ibl wait");
    }
};

void barrier(VkCommandBuffer cmd, VkImage image, VkImageLayout from, VkImageLayout to, VkPipelineStageFlags2 src_stage,
             VkAccessFlags2 src_access, VkPipelineStageFlags2 dst_stage, VkAccessFlags2 dst_access) {
    VkImageMemoryBarrier2 b{.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
    b.srcStageMask = src_stage;
    b.srcAccessMask = src_access;
    b.dstStageMask = dst_stage;
    b.dstAccessMask = dst_access;
    b.oldLayout = from;
    b.newLayout = to;
    b.image = image;
    b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, VK_REMAINING_MIP_LEVELS, 0, VK_REMAINING_ARRAY_LAYERS};
    VkDependencyInfo dep{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    dep.imageMemoryBarrierCount = 1;
    dep.pImageMemoryBarriers = &b;
    vkCmdPipelineBarrier2(cmd, &dep);
}

/** Copy regions of a square image (size, levels, layers) packed level after level, layers adjacent; total bytes in bytes. */
std::vector<VkBufferImageCopy> packed_regions(uint32_t size, uint32_t levels, uint32_t layers, VkDeviceSize first,
                                              VkDeviceSize& bytes) {
    std::vector<VkBufferImageCopy> regions;
    bytes = first;
    for (uint32_t l = 0; l < levels; l++) {
        const uint32_t s = std::max(1u, size >> l);
        VkBufferImageCopy r{};
        r.bufferOffset = bytes;
        r.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, l, 0, layers};
        r.imageExtent = {s, s, 1};
        regions.push_back(r);
        bytes += VkDeviceSize{s} * s * kTexelBytes * layers;
    }
    return regions;
}

/** One cache file: the packed image at data plus the hash (and SH9 when sh is non-null) as KTX2 metadata. */
void write_ktx2(const std::string& path, const uint8_t* data, uint32_t size, uint32_t levels, uint32_t faces,
                uint64_t hash, const void* sh) {
    ktxTextureCreateInfo info{};
    info.vkFormat = kFormat;
    info.baseWidth = info.baseHeight = size;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = levels;
    info.numLayers = 1;
    info.numFaces = faces;
    ktxTexture2* tex = nullptr;
    if (ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex) != KTX_SUCCESS) throw std::runtime_error("ktx2 create");
    for (uint32_t l = 0; l < levels; l++) {
        const uint32_t s = std::max(1u, size >> l);
        const size_t face_bytes = size_t{s} * s * kTexelBytes;
        for (uint32_t f = 0; f < faces; f++, data += face_bytes)
            ktxTexture_SetImageFromMemory(ktxTexture(tex), l, 0, f, data, face_bytes);
    }
    ktxHashList_AddKVPair(&tex->kvDataHead, kHashKey, sizeof(hash), &hash);
    if (sh) ktxHashList_AddKVPair(&tex->kvDataHead, kShKey, kShBytes, sh);
    const KTX_error_code written = ktxTexture_WriteToNamedFile(ktxTexture(tex), path.c_str());
    ktxTexture_Destroy(ktxTexture(tex));
    if (written != KTX_SUCCESS) std::printf("IBL cache write failed path=%s\n", path.c_str());
}

/** Appends a cache file's levels to out (packed like packed_regions) when its hash and shape match; copies SH9 into sh when non-null. */
bool read_ktx2(const std::string& path, uint64_t hash, uint32_t size, uint32_t levels, uint32_t faces,
               std::vector<uint8_t>& out, void* sh) {
    ktxTexture2* tex = nullptr;
    if (ktxTexture2_CreateFromNamedFile(path.c_str(), KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT, &tex) != KTX_SUCCESS) return false;
    unsigned int len = 0;
    void* value = nullptr;
    bool ok = tex->vkFormat == kFormat && tex->baseWidth == size && tex->numLevels == levels && tex->numFaces == faces &&
              ktxHashList_FindValue(&tex->kvDataHead, kHashKey, &len, &value) == KTX_SUCCESS && len == sizeof(hash) &&
              std::memcmp(value, &hash, sizeof(hash)) == 0;
    if (ok && sh) ok = ktxHashList_FindValue(&tex->kvDataHead, kShKey, &len, &value) == KTX_SUCCESS && len == kShBytes;
    if (ok && sh) std::memcpy(sh, value, kShBytes);
    for (uint32_t l = 0; ok && l < levels; l++) {
        const uint32_t s = std::max(1u, size >> l);
        for (uint32_t f = 0; f < faces; f++) {
            ktx_size_t offset = 0;
            ktxTexture_GetImageOffset(ktxTexture(tex), l, 0, f, &offset);
            const uint8_t* p = ktxTexture_GetData(ktxTexture(tex)) + offset;
            out.insert(out.end(), p, p + size_t{s} * s * kTexelBytes);
        }
    }
    ktxTexture_Destroy(ktxTexture(tex));
    return ok;
}

VkImageView create_view(VkDevice dev, VkImage image, VkImageViewType type, uint32_t level, uint32_t levels, uint32_t layers) {
    VkImageViewCreateInfo info{.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    info.image = image;
    info.viewType = type;
    info.format = kFormat;
    info.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, level, levels, 0, layers};
    VkImageView view;
    check(vkCreateImageView(dev, &info, nullptr, &view), "ibl view");
    return view;
}

VkSampler create_sampler(VkDevice dev, VkSamplerAddressMode u, VkSamplerAddressMode v) {
    VkSamplerCreateInfo info{.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    info.magFilter = info.minFilter = VK_FILTER_LINEAR;
    info.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    info.addressModeU = u;
    info.addressModeV = info.addressModeW = v;
    info.maxLod = VK_LOD_CLAMP_NONE;
    VkSampler sampler;
    check(vkCreateSampler(dev, &info, nullptr, &sampler), "ibl sampler");
    return sampler;
}

}  // namespace

Ibl::Ibl(GpuContext& gpu, const std::string& hdr)
    : gpu_(gpu),
      sh_(create_buffer(gpu, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, kNoSh.data(), kShBytes)),
      sampler_(create_sampler(gpu.device(), VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE, VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE)) {
    if (hdr.empty() || !std::filesystem::exists(hdr)) {
        create_targets(1, 1, 1);
        clear_placeholders();
        std::printf("IBL off source=%s\n", hdr.empty() ? "none" : hdr.c_str());
        return;
    }
    const auto t0 = std::chrono::steady_clock::now();
    const uint64_t hash = fnv1a(read_file(std::string(GAME_SHADER_DIR) + "/ibl_prefilter.comp.spv"), fnv1a(read_file(hdr)));
    create_targets(kCubeSize, kMips, kLutSize);
    const bool hit = load_cache(hdr, hash);
    if (!hit) bake(hdr, hash);
    enabled_ = true;
    const double cpu_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    std::printf("IBL source=%s cache=%s bake_gpu_ms=%.3f load_ms=%.1f cube=%u mips=%u lut=%u\n", hdr.c_str(),
                hit ? "hit" : "miss", bake_ms_.value_or(0.0), cpu_ms, kCubeSize, kMips, kLutSize);
}

Ibl::~Ibl() {
    VkDevice dev = gpu_.device();
    vkDestroySampler(dev, sampler_, nullptr);
    vkDestroyImageView(dev, cube_view_, nullptr);
    vmaDestroyImage(gpu_.allocator(), cube_, cube_alloc_);
    destroy_color_image(gpu_, lut_);
    destroy_buffer(gpu_, sh_);
}

void Ibl::create_targets(uint32_t cube_size, uint32_t mips, uint32_t lut_size) {
    VkImageCreateInfo info{.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.flags = VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = kFormat;
    info.extent = {cube_size, cube_size, 1};
    info.mipLevels = mips;
    info.arrayLayers = 6;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                 VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    VmaAllocationCreateInfo alloc{};
    alloc.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
    check(vmaCreateImage(gpu_.allocator(), &info, &alloc, &cube_, &cube_alloc_, nullptr), "ibl cube");
    cube_view_ = create_view(gpu_.device(), cube_, VK_IMAGE_VIEW_TYPE_CUBE, 0, mips, 6);
    lut_ = create_color_image(gpu_, {lut_size, lut_size}, kFormat,
                              VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                                  VK_IMAGE_USAGE_TRANSFER_DST_BIT);
}

void Ibl::clear_placeholders() {
    OneShot once(gpu_);
    const VkClearColorValue black{};
    const VkImageSubresourceRange all{VK_IMAGE_ASPECT_COLOR_BIT, 0, VK_REMAINING_MIP_LEVELS, 0, VK_REMAINING_ARRAY_LAYERS};
    for (VkImage image : {cube_, lut_.image}) {
        barrier(once.cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_2_NONE, 0,
                VK_PIPELINE_STAGE_2_CLEAR_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT);
        vkCmdClearColorImage(once.cmd, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &black, 1, &all);
        barrier(once.cmd, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                VK_PIPELINE_STAGE_2_CLEAR_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
                VK_ACCESS_2_SHADER_SAMPLED_READ_BIT);
    }
    once.submit_and_wait();
}

bool Ibl::load_cache(const std::string& hdr, uint64_t hash) {
    std::vector<uint8_t> data;
    if (!read_ktx2(hdr + ".ibl.ktx2", hash, kCubeSize, kMips, 6, data, sh_.mapped)) return false;
    const VkDeviceSize lut_first = data.size();
    if (!read_ktx2(hdr + ".lut.ktx2", hash, kLutSize, 1, 1, data, nullptr)) return false;
    VkDeviceSize end = 0;
    const std::vector<VkBufferImageCopy> cube_regions = packed_regions(kCubeSize, kMips, 6, 0, end);
    const std::vector<VkBufferImageCopy> lut_regions = packed_regions(kLutSize, 1, 1, lut_first, end);
    Buffer staging = create_buffer(gpu_, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, data.data(), data.size());
    OneShot once(gpu_);
    for (VkImage image : {cube_, lut_.image})
        barrier(once.cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_2_NONE, 0,
                VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT);
    vkCmdCopyBufferToImage(once.cmd, staging.buffer, cube_, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                           static_cast<uint32_t>(cube_regions.size()), cube_regions.data());
    vkCmdCopyBufferToImage(once.cmd, staging.buffer, lut_.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, lut_regions.data());
    for (VkImage image : {cube_, lut_.image})
        barrier(once.cmd, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
                VK_ACCESS_2_SHADER_SAMPLED_READ_BIT);
    once.submit_and_wait();
    destroy_buffer(gpu_, staging);
    return true;
}

/** Push constants of ibl_prefilter.comp. */
struct BakePush {
    uint32_t mode;
    float roughness;
};

void Ibl::bake(const std::string& hdr, uint64_t hash) {
    VkDevice dev = gpu_.device();
    uint32_t w = 0, h = 0;
    std::vector<VkDeviceSize> offsets;
    const std::vector<uint16_t> texels = half_mips(decode_hdr(read_file(hdr), w, h), w, h, offsets);
    const auto env_levels = static_cast<uint32_t>(offsets.size());

    VkImageCreateInfo info{.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = kFormat;
    info.extent = {w, h, 1};
    info.mipLevels = env_levels;
    info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    VmaAllocationCreateInfo alloc{};
    alloc.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
    VkImage env;
    VmaAllocation env_alloc;
    check(vmaCreateImage(gpu_.allocator(), &info, &alloc, &env, &env_alloc, nullptr), "ibl env");
    VkImageView env_view = create_view(dev, env, VK_IMAGE_VIEW_TYPE_2D, 0, env_levels, 1);
    VkSampler env_sampler = create_sampler(dev, VK_SAMPLER_ADDRESS_MODE_REPEAT, VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE);
    Buffer staging = create_buffer(gpu_, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, texels.data(), texels.size() * sizeof(uint16_t));
    VkDeviceSize readback_bytes = 0;
    const std::vector<VkBufferImageCopy> cube_regions = packed_regions(kCubeSize, kMips, 6, 0, readback_bytes);
    const VkDeviceSize lut_first = readback_bytes;
    const std::vector<VkBufferImageCopy> lut_regions = packed_regions(kLutSize, 1, 1, lut_first, readback_bytes);
    Buffer readback = create_buffer(gpu_, VK_BUFFER_USAGE_TRANSFER_DST_BIT, nullptr, readback_bytes);

    // Storage views: one 2D array (6 faces) per cube mip, then the LUT as a 1-layer array.
    std::array<VkImageView, kMips + 1> dst_views{};
    for (uint32_t l = 0; l < kMips; l++) dst_views[l] = create_view(dev, cube_, VK_IMAGE_VIEW_TYPE_2D_ARRAY, l, 1, 6);
    dst_views[kMips] = create_view(dev, lut_.image, VK_IMAGE_VIEW_TYPE_2D_ARRAY, 0, 1, 1);

    const VkDescriptorSetLayoutBinding bindings[3] = {
        {0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo set_info{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    set_info.bindingCount = 3;
    set_info.pBindings = bindings;
    VkDescriptorSetLayout set_layout;
    check(vkCreateDescriptorSetLayout(dev, &set_info, nullptr, &set_layout), "ibl set layout");
    const VkPushConstantRange push_range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(BakePush)};
    VkPipelineLayoutCreateInfo layout_info{.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    layout_info.setLayoutCount = 1;
    layout_info.pSetLayouts = &set_layout;
    layout_info.pushConstantRangeCount = 1;
    layout_info.pPushConstantRanges = &push_range;
    VkPipelineLayout layout;
    check(vkCreatePipelineLayout(dev, &layout_info, nullptr, &layout), "ibl pipeline layout");
    VkComputePipelineCreateInfo pipe_info{.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    pipe_info.stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                       .module = load_shader(dev, "ibl_prefilter.comp.spv"), .pName = "main"};
    pipe_info.layout = layout;
    VkPipeline pipeline;
    const VkResult created = vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &pipe_info, nullptr, &pipeline);
    vkDestroyShaderModule(dev, pipe_info.stage.module, nullptr);
    check(created, "ibl pipeline");

    constexpr uint32_t kSets = kMips + 1;
    const VkDescriptorPoolSize sizes[3] = {{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, kSets},
                                           {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, kSets},
                                           {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, kSets}};
    VkDescriptorPoolCreateInfo pool_info{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pool_info.maxSets = kSets;
    pool_info.poolSizeCount = 3;
    pool_info.pPoolSizes = sizes;
    VkDescriptorPool pool;
    check(vkCreateDescriptorPool(dev, &pool_info, nullptr, &pool), "ibl pool");
    std::array<VkDescriptorSetLayout, kSets> layouts;
    layouts.fill(set_layout);
    std::array<VkDescriptorSet, kSets> sets{};
    VkDescriptorSetAllocateInfo set_alloc{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    set_alloc.descriptorPool = pool;
    set_alloc.descriptorSetCount = kSets;
    set_alloc.pSetLayouts = layouts.data();
    check(vkAllocateDescriptorSets(dev, &set_alloc, sets.data()), "ibl sets");
    const VkDescriptorImageInfo src{env_sampler, env_view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    const VkDescriptorBufferInfo sh{sh_.buffer, 0, kShBytes};
    std::array<VkDescriptorImageInfo, kSets> dst{};
    std::vector<VkWriteDescriptorSet> writes;
    for (uint32_t s = 0; s < kSets; s++) {
        dst[s] = {VK_NULL_HANDLE, dst_views[s], VK_IMAGE_LAYOUT_GENERAL};
        writes.push_back({.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = sets[s], .dstBinding = 0,
                          .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &src});
        writes.push_back({.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = sets[s], .dstBinding = 1,
                          .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .pImageInfo = &dst[s]});
        writes.push_back({.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = sets[s], .dstBinding = 2,
                          .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &sh});
    }
    vkUpdateDescriptorSets(dev, static_cast<uint32_t>(writes.size()), writes.data(), 0, nullptr);

    GpuTimer timer(gpu_, 1);
    {
        OneShot once(gpu_);
        VkCommandBuffer cmd = once.cmd;
        barrier(cmd, env, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_2_NONE, 0,
                VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT);
        std::vector<VkBufferImageCopy> env_regions(env_levels);
        for (uint32_t l = 0; l < env_levels; l++) {
            env_regions[l].bufferOffset = offsets[l];
            env_regions[l].imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, l, 0, 1};
            env_regions[l].imageExtent = {std::max(1u, w >> l), std::max(1u, h >> l), 1};
        }
        vkCmdCopyBufferToImage(cmd, staging.buffer, env, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, env_levels, env_regions.data());
        barrier(cmd, env, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                VK_ACCESS_2_SHADER_SAMPLED_READ_BIT);
        for (VkImage image : {cube_, lut_.image})
            barrier(cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL, VK_PIPELINE_STAGE_2_NONE, 0,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);

        timer.begin(cmd, 0);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        for (uint32_t s = 0; s < kSets; s++) {
            const bool lut = s == kMips;
            const BakePush push{lut ? 1u : 0u, lut ? 0.0f : float(s) / float(kMips - 1)};
            const uint32_t size = lut ? kLutSize : kCubeSize >> s;
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &sets[s], 0, nullptr);
            vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
            vkCmdDispatch(cmd, (size + 7) / 8, (size + 7) / 8, lut ? 1 : 6);
        }
        const BakePush sh_push{2u, 0.0f};
        vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(sh_push), &sh_push);
        vkCmdDispatch(cmd, 1, 1, 1);
        timer.end(cmd, 0);

        for (VkImage image : {cube_, lut_.image})
            barrier(cmd, image, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT, VK_PIPELINE_STAGE_2_COPY_BIT,
                    VK_ACCESS_2_TRANSFER_READ_BIT);
        vkCmdCopyImageToBuffer(cmd, cube_, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer,
                               static_cast<uint32_t>(cube_regions.size()), cube_regions.data());
        vkCmdCopyImageToBuffer(cmd, lut_.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, lut_regions.data());
        for (VkImage image : {cube_, lut_.image})
            barrier(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    VK_PIPELINE_STAGE_2_COPY_BIT, 0, VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, VK_ACCESS_2_SHADER_SAMPLED_READ_BIT);
        VkMemoryBarrier2 to_host{.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2};
        to_host.srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT | VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
        to_host.srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT;
        to_host.dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT | VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
        to_host.dstAccessMask = VK_ACCESS_2_HOST_READ_BIT | VK_ACCESS_2_UNIFORM_READ_BIT;
        VkDependencyInfo dep{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
        dep.memoryBarrierCount = 1;
        dep.pMemoryBarriers = &to_host;
        vkCmdPipelineBarrier2(cmd, &dep);
        once.submit_and_wait();
    }
    bake_ms_ = timer.collect(0);

    const auto* bytes = static_cast<const uint8_t*>(readback.mapped);
    write_ktx2(hdr + ".ibl.ktx2", bytes, kCubeSize, kMips, 6, hash, sh_.mapped);
    write_ktx2(hdr + ".lut.ktx2", bytes + lut_first, kLutSize, 1, 1, hash, nullptr);

    vkDestroyDescriptorPool(dev, pool, nullptr);
    vkDestroyPipeline(dev, pipeline, nullptr);
    vkDestroyPipelineLayout(dev, layout, nullptr);
    vkDestroyDescriptorSetLayout(dev, set_layout, nullptr);
    for (VkImageView v : dst_views) vkDestroyImageView(dev, v, nullptr);
    destroy_buffer(gpu_, readback);
    destroy_buffer(gpu_, staging);
    vkDestroySampler(dev, env_sampler, nullptr);
    vkDestroyImageView(dev, env_view, nullptr);
    vmaDestroyImage(gpu_.allocator(), env, env_alloc);
}
