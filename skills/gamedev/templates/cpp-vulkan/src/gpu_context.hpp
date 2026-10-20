#pragma once

#include <volk.h>
#include <VkBootstrap.h>
#include <vk_mem_alloc.h>

#include <cstdint>
#include <vector>

struct SDL_Window;

/** Counts validation messages by severity. */
struct ValidationCounts {
    uint32_t errors = 0;
    uint32_t warnings = 0;
};

/** Device-local heap bytes from VMA: used is -1 without VK_EXT_memory_budget, budget is then VMA's estimate. */
struct VramUsage {
    int64_t used = -1;
    uint64_t budget = 0;
};

/** Owns the Vulkan instance, surface, device, VMA allocator, graphics queue and swapchain. */
class GpuContext {
public:
    GpuContext(SDL_Window* window, bool validate);
    ~GpuContext();
    GpuContext(const GpuContext&) = delete;
    GpuContext& operator=(const GpuContext&) = delete;

    bool recreate_swapchain();

    VkDevice device() const { return device_.device; }
    VmaAllocator allocator() const { return allocator_; }
    VkPhysicalDevice physical_device() const { return physical_.physical_device; }
    VkQueue queue() const { return queue_; }
    uint32_t queue_family() const { return queue_family_; }
    VkSwapchainKHR swapchain() const { return swapchain_.swapchain; }
    VkExtent2D extent() const { return swapchain_.extent; }
    VkFormat format() const { return swapchain_.image_format; }
    VkPresentModeKHR present_mode() const { return swapchain_.present_mode; }
    const std::vector<VkImage>& images() const { return images_; }
    const std::vector<VkImageView>& image_views() const { return views_; }
    const char* device_name() const { return physical_.properties.deviceName; }
    const ValidationCounts& validation() const { return counts_; }
    float timestamp_period() const { return physical_.properties.limits.timestampPeriod; }
    uint32_t timestamp_bits() const { return timestamp_bits_; }
    float max_anisotropy() const { return physical_.properties.limits.maxSamplerAnisotropy; }
    /** The optional features enabled on the device (anisotropy, BC and ETC2 compression). */
    const VkPhysicalDeviceFeatures& features() const { return features_; }
    VramUsage vram() const;

private:
    void destroy_swapchain_views();

    SDL_Window* window_;
    ValidationCounts counts_;
    vkb::Instance instance_;
    VkSurfaceKHR surface_ = VK_NULL_HANDLE;
    vkb::PhysicalDevice physical_;
    vkb::Device device_;
    VmaAllocator allocator_ = VK_NULL_HANDLE;
    VkQueue queue_ = VK_NULL_HANDLE;
    uint32_t queue_family_ = 0;
    uint32_t timestamp_bits_ = 0;
    bool memory_budget_ = false;
    VkPhysicalDeviceFeatures features_{};
    vkb::Swapchain swapchain_;
    std::vector<VkImage> images_;
    std::vector<VkImageView> views_;
};
