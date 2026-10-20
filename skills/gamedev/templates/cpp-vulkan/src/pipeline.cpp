#include "pipeline.hpp"

#include "mesh.hpp"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <stdexcept>
#include <vector>

namespace {

void check(VkResult result, const char* what) {
    if (result != VK_SUCCESS) throw std::runtime_error(what);
}

std::vector<char> read_file(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return {};
    return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}

std::string cache_file(const char* name) {
    const char* xdg = std::getenv("XDG_CACHE_HOME");
    const char* home = std::getenv("HOME");
    std::filesystem::path dir = xdg && *xdg ? xdg : std::filesystem::path(home ? home : ".") / ".cache";
    return (dir / GAME_NAME / name).string();
}

struct ReloadHook {
    std::vector<std::string> spv;
    std::function<void()> rebuild;
};

std::map<const void*, ReloadHook>& reload_hooks() {
    static std::map<const void*, ReloadHook> hooks;
    return hooks;
}

}  // namespace

void add_reload_hook(const void* owner, std::vector<std::string> spv, std::function<void()> rebuild) {
    reload_hooks()[owner] = {std::move(spv), std::move(rebuild)};
}

void remove_reload_hook(const void* owner) { reload_hooks().erase(owner); }

int reload_pipelines(const std::string& spv) {
    int ran = 0;
    for (auto& [owner, hook] : reload_hooks()) {
        if (std::find(hook.spv.begin(), hook.spv.end(), spv) == hook.spv.end()) continue;
        hook.rebuild();
        ran++;
    }
    return ran;
}

VkShaderModule load_shader(VkDevice device, const char* name) {
    const std::string path = std::string(GAME_SHADER_DIR) + "/" + name;
    std::vector<char> code = read_file(path);
    if (code.empty()) throw std::runtime_error("shader missing: " + path);
    VkShaderModuleCreateInfo info{.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    info.codeSize = code.size();
    info.pCode = reinterpret_cast<const uint32_t*>(code.data());
    VkShaderModule module;
    check(vkCreateShaderModule(device, &info, nullptr, &module), "shader module");
    return module;
}

MeshPipeline::MeshPipeline(const GpuContext& gpu, VkFormat color_format, VkFormat depth_format,
                           const std::vector<VkDescriptorSetLayout>& sets, bool skinned)
    : device_(gpu.device()), color_format_(color_format), depth_format_(depth_format), skinned_(skinned),
      cache_path_(cache_file(skinned ? "skinned.cache" : "pipeline.cache")) {
    std::vector<char> blob = read_file(cache_path_);
    VkPipelineCacheCreateInfo cache_info{.sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO};
    cache_info.initialDataSize = blob.size();
    cache_info.pInitialData = blob.data();
    check(vkCreatePipelineCache(device_, &cache_info, nullptr, &cache_), "pipeline cache");

    VkPushConstantRange push{VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(MeshPush)};
    VkPipelineLayoutCreateInfo layout_info{.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    layout_info.setLayoutCount = static_cast<uint32_t>(sets.size());
    layout_info.pSetLayouts = sets.data();
    layout_info.pushConstantRangeCount = 1;
    layout_info.pPushConstantRanges = &push;
    check(vkCreatePipelineLayout(device_, &layout_info, nullptr, &layout_), "pipeline layout");

    const auto t0 = std::chrono::steady_clock::now();
    build();
    const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    std::printf("PIPELINE create_ms=%.3f cache_bytes_in=%zu cache=%s\n", ms, blob.size(), cache_path_.c_str());
    add_reload_hook(this, skinned_ ? std::vector<std::string>{"skinned.vert.spv", "mesh.frag.spv"}
                                   : std::vector<std::string>{"mesh.vert.spv", "mesh.frag.spv", "shadow.vert.spv"},
                    [this] { build(); });
}

void MeshPipeline::build() {
    VkShaderModule vert = load_shader(device_, skinned_ ? "skinned.vert.spv" : "mesh.vert.spv");
    VkShaderModule frag = load_shader(device_, "mesh.frag.spv");
    VkPipelineShaderStageCreateInfo stages[2] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT,
         .module = vert, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
         .module = frag, .pName = "main"},
    };
    const VkVertexInputBindingDescription bindings[2] = {{0, sizeof(Vertex), VK_VERTEX_INPUT_RATE_VERTEX},
                                                        {1, sizeof(SkinVertex), VK_VERTEX_INPUT_RATE_VERTEX}};
    const VkVertexInputAttributeDescription attributes[6] = {
        {0, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(Vertex, position)},
        {1, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(Vertex, normal)},
        {2, 0, VK_FORMAT_R32G32_SFLOAT, offsetof(Vertex, uv)},
        {3, 0, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(Vertex, tangent)},
        {4, 1, VK_FORMAT_R16G16B16A16_UINT, offsetof(SkinVertex, joints)},
        {5, 1, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(SkinVertex, weights)},
    };
    VkPipelineVertexInputStateCreateInfo vertex_input{.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    vertex_input.vertexBindingDescriptionCount = skinned_ ? 2 : 1;
    vertex_input.pVertexBindingDescriptions = bindings;
    vertex_input.vertexAttributeDescriptionCount = skinned_ ? 6 : 4;
    vertex_input.pVertexAttributeDescriptions = attributes;
    VkPipelineInputAssemblyStateCreateInfo assembly{.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkPipelineViewportStateCreateInfo viewport{.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    viewport.viewportCount = 1;
    viewport.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo raster{.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    raster.polygonMode = VK_POLYGON_MODE_FILL;
    raster.cullMode = VK_CULL_MODE_BACK_BIT;
    raster.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    raster.lineWidth = 1.0f;
    VkPipelineMultisampleStateCreateInfo multisample{.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo depth{.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    depth.depthTestEnable = VK_TRUE;
    depth.depthWriteEnable = VK_TRUE;
    depth.depthCompareOp = VK_COMPARE_OP_LESS;
    VkPipelineColorBlendAttachmentState blend_attachment{};
    blend_attachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                                      VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    VkPipelineColorBlendStateCreateInfo blend{.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    blend.attachmentCount = 1;
    blend.pAttachments = &blend_attachment;
    VkDynamicState dynamic_states[2] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic{.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dynamic.dynamicStateCount = 2;
    dynamic.pDynamicStates = dynamic_states;
    VkPipelineRenderingCreateInfo rendering{.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    rendering.colorAttachmentCount = 1;
    rendering.pColorAttachmentFormats = &color_format_;
    rendering.depthAttachmentFormat = depth_format_;

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
    info.layout = layout_;
    VkPipeline lit = VK_NULL_HANDLE, shadow = VK_NULL_HANDLE;
    VkResult created = vkCreateGraphicsPipelines(device_, cache_, 1, &info, nullptr, &lit);
    vkDestroyShaderModule(device_, vert, nullptr);
    vkDestroyShaderModule(device_, frag, nullptr);
    check(created, "graphics pipeline");

    VkShaderModule shadow_vert = load_shader(device_, skinned_ ? "skinned.vert.spv" : "shadow.vert.spv");
    stages[0].module = shadow_vert;
    info.stageCount = 1;
    if (!skinned_) vertex_input.vertexAttributeDescriptionCount = 1;
    raster.depthBiasEnable = VK_TRUE;
    raster.depthBiasConstantFactor = 1.25f;
    raster.depthBiasSlopeFactor = 1.75f;
    blend.attachmentCount = 0;
    rendering.colorAttachmentCount = 0;
    created = vkCreateGraphicsPipelines(device_, cache_, 1, &info, nullptr, &shadow);
    vkDestroyShaderModule(device_, shadow_vert, nullptr);
    if (created != VK_SUCCESS) vkDestroyPipeline(device_, lit, nullptr);
    check(created, "shadow pipeline");
    vkDestroyPipeline(device_, pipeline_, nullptr);
    vkDestroyPipeline(device_, shadow_, nullptr);
    pipeline_ = lit;
    shadow_ = shadow;
}

MeshPipeline::~MeshPipeline() {
    remove_reload_hook(this);
    size_t size = 0;
    if (vkGetPipelineCacheData(device_, cache_, &size, nullptr) == VK_SUCCESS && size > 0) {
        std::vector<char> data(size);
        if (vkGetPipelineCacheData(device_, cache_, &size, data.data()) == VK_SUCCESS) {
            std::error_code ec;
            std::filesystem::create_directories(std::filesystem::path(cache_path_).parent_path(), ec);
            const std::string tmp = cache_path_ + ".tmp";
            std::ofstream(tmp, std::ios::binary).write(data.data(), static_cast<std::streamsize>(size));
            std::filesystem::rename(tmp, cache_path_, ec);
        }
    }
    vkDestroyPipeline(device_, shadow_, nullptr);
    vkDestroyPipeline(device_, pipeline_, nullptr);
    vkDestroyPipelineLayout(device_, layout_, nullptr);
    vkDestroyPipelineCache(device_, cache_, nullptr);
}
