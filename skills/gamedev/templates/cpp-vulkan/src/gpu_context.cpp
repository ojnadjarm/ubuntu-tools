#include "gpu_context.hpp"

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>

#include <cstdio>
#include <stdexcept>
#include <string>

namespace {

VKAPI_ATTR VkBool32 VKAPI_CALL on_debug_message(VkDebugUtilsMessageSeverityFlagBitsEXT severity,
                                                VkDebugUtilsMessageTypeFlagsEXT,
                                                const VkDebugUtilsMessengerCallbackDataEXT* data,
                                                void* user) {
    auto* counts = static_cast<ValidationCounts*>(user);
    if (severity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) {
        counts->errors++;
        std::fprintf(stderr, "VALIDATION ERROR: [%s] %s\n", data->pMessageIdName ? data->pMessageIdName : "",
                     data->pMessage);
    } else if (severity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        counts->warnings++;
        std::fprintf(stderr, "VALIDATION WARNING: [%s] %s\n", data->pMessageIdName ? data->pMessageIdName : "",
                     data->pMessage);
    }
    return VK_FALSE;
}

template <typename T>
T unwrap(vkb::Result<T> result, const char* what) {
    if (!result) throw std::runtime_error(std::string(what) + ": " + result.error().message());
    return result.value();
}

}  // namespace

GpuContext::GpuContext(SDL_Window* window, bool validate) : window_(window) {
    if (volkInitialize() != VK_SUCCESS) throw std::runtime_error("no Vulkan loader");

    Uint32 ext_count = 0;
    const char* const* exts = SDL_Vulkan_GetInstanceExtensions(&ext_count);
    vkb::InstanceBuilder builder{vkGetInstanceProcAddr};
    builder.set_app_name("cpp-vulkan-game").require_api_version(1, 3, 0);
    for (Uint32 i = 0; i < ext_count; i++) builder.enable_extension(exts[i]);
    if (validate) {
        builder.enable_validation_layers()
            .set_debug_callback(on_debug_message)
            .set_debug_callback_user_data_pointer(&counts_)
            .set_debug_messenger_severity(VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                                          VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT);
    }
    instance_ = unwrap(builder.build(), "instance");
    volkLoadInstance(instance_.instance);

    if (!SDL_Vulkan_CreateSurface(window_, instance_.instance, nullptr, &surface_))
        throw std::runtime_error(std::string("surface: ") + SDL_GetError());

    VkPhysicalDeviceVulkan13Features features13{.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    features13.synchronization2 = VK_TRUE;
    features13.dynamicRendering = VK_TRUE;
    features13.shaderDemoteToHelperInvocation = VK_TRUE;
    physical_ = unwrap(vkb::PhysicalDeviceSelector{instance_}
                           .set_surface(surface_)
                           .set_minimum_version(1, 3)
                           .set_required_features_13(features13)
                           .select(),
                       "physical device");
    memory_budget_ = physical_.enable_extension_if_present(VK_EXT_MEMORY_BUDGET_EXTENSION_NAME);
    features_.samplerAnisotropy = physical_.enable_features_if_present({.samplerAnisotropy = VK_TRUE});
    features_.textureCompressionBC = physical_.enable_features_if_present({.textureCompressionBC = VK_TRUE});
    features_.textureCompressionETC2 = physical_.enable_features_if_present({.textureCompressionETC2 = VK_TRUE});
    device_ = unwrap(vkb::DeviceBuilder{physical_}.build(), "device");
    volkLoadDevice(device_.device);
    VmaVulkanFunctions functions{.vkGetInstanceProcAddr = vkGetInstanceProcAddr,
                                 .vkGetDeviceProcAddr = vkGetDeviceProcAddr};
    VmaAllocatorCreateInfo allocator_info{.flags = memory_budget_ ? VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT : 0u,
                                          .physicalDevice = physical_.physical_device,
                                          .device = device_.device,
                                          .pVulkanFunctions = &functions,
                                          .instance = instance_.instance,
                                          .vulkanApiVersion = VK_API_VERSION_1_3};
    if (vmaCreateAllocator(&allocator_info, &allocator_) != VK_SUCCESS) throw std::runtime_error("VMA allocator");
    queue_ = unwrap(device_.get_queue(vkb::QueueType::graphics), "queue");
    queue_family_ = unwrap(device_.get_queue_index(vkb::QueueType::graphics), "queue index");
    if (physical_.properties.limits.timestampComputeAndGraphics)
        timestamp_bits_ = physical_.get_queue_families()[queue_family_].timestampValidBits;

    if (!recreate_swapchain()) throw std::runtime_error("swapchain");
}

VramUsage GpuContext::vram() const {
    vmaSetCurrentFrameIndex(allocator_, 0);  // refreshes the driver's VK_EXT_memory_budget numbers
    VmaBudget budgets[VK_MAX_MEMORY_HEAPS];
    vmaGetHeapBudgets(allocator_, budgets);
    const VkPhysicalDeviceMemoryProperties* props = nullptr;
    vmaGetMemoryProperties(allocator_, &props);
    VramUsage usage{.used = memory_budget_ ? 0 : -1};
    for (uint32_t i = 0; i < props->memoryHeapCount; i++) {
        if (!(props->memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT)) continue;
        if (memory_budget_) usage.used += static_cast<int64_t>(budgets[i].usage);
        usage.budget += budgets[i].budget;
    }
    return usage;
}

GpuContext::~GpuContext() {
    vkDeviceWaitIdle(device_.device);
    VmaTotalStatistics stats;
    vmaCalculateStatistics(allocator_, &stats);
    std::printf("VMA live_allocations=%u live_bytes=%llu\n", stats.total.statistics.allocationCount,
                static_cast<unsigned long long>(stats.total.statistics.allocationBytes));
    std::fflush(stdout);
    vmaDestroyAllocator(allocator_);
    destroy_swapchain_views();
    vkb::destroy_swapchain(swapchain_);
    vkb::destroy_device(device_);
    vkb::destroy_surface(instance_, surface_);
    vkb::destroy_instance(instance_);
}

bool GpuContext::recreate_swapchain() {
    int w = 0, h = 0;
    SDL_GetWindowSizeInPixels(window_, &w, &h);
    if (w == 0 || h == 0) return false;

    vkDeviceWaitIdle(device_.device);
    auto result = vkb::SwapchainBuilder{device_}
                      .set_old_swapchain(swapchain_)
                      .set_desired_extent(static_cast<uint32_t>(w), static_cast<uint32_t>(h))
                      .set_desired_format({VK_FORMAT_B8G8R8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR})
                      .set_desired_present_mode(VK_PRESENT_MODE_MAILBOX_KHR)
                      .add_fallback_present_mode(VK_PRESENT_MODE_FIFO_KHR)
                      .set_image_usage_flags(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT)
                      .build();
    if (!result) return false;

    destroy_swapchain_views();
    vkb::destroy_swapchain(swapchain_);
    swapchain_ = result.value();
    images_ = unwrap(swapchain_.get_images(), "swapchain images");
    views_ = unwrap(swapchain_.get_image_views(), "swapchain views");
    return true;
}

void GpuContext::destroy_swapchain_views() {
    if (!views_.empty()) swapchain_.destroy_image_views(views_);
    views_.clear();
}
