#pragma once

#include "gpu_context.hpp"
#include "gpu_resources.hpp"
#include "gpu_timer.hpp"
#include "ibl.hpp"
#include "mesh.hpp"
#include "pipeline.hpp"
#include "post.hpp"
#include "skinned_draw.hpp"
#include "texture.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

/** Draws, frustum-culled draws and scene instances per LOD in the last recorded frame. */
struct DrawStats {
    uint32_t draws = 0;
    uint32_t culled = 0;
    std::array<uint32_t, 3> lods{};
};

/** Records and presents one frame per call (a directional shadow-map pass, a PBR draw per scene node primitive lit by the sun and image-based lighting and an optional animated character on a shadowed ground into an HDR target, then bloom + AgX into the swapchain), two frames in flight. */
class Renderer {
public:
    /** character: the player's body, placed by set_character; environment: an equirectangular .hdr lighting the scene (empty: hemisphere sky). */
    Renderer(GpuContext& gpu, const SceneData& scene, std::optional<SkinnedModel> character = std::nullopt,
             const std::string& environment = "");
    ~Renderer();
    Renderer(const Renderer&) = delete;
    Renderer& operator=(const Renderer&) = delete;

    void draw_frame(const VkClearColorValue& color, float seconds);
    std::optional<double> gpu_ms() const { return gpu_ms_; }
    /** GPU time of the post chain (bloom + tonemap) in the last collected frame. */
    std::optional<double> post_ms() const { return pass_ms(GpuPass::Post); }
    /** GPU time of one render pass in the last collected frame. */
    std::optional<double> pass_ms(GpuPass pass) const { return pass_ms_[static_cast<size_t>(pass)]; }
    uint64_t blocked_ns() const { return blocked_ns_; }
    /** Saves the next drawn frame as a PNG at path (read back from the swapchain image). */
    void capture_next(std::string path) { capture_path_ = std::move(path); }
    /** Replaces the built-in camera (eye at 0,0.8,2.6 looking at the origin) with a view-projection matrix. */
    void set_view_proj(const glm::mat4& view_proj) { view_proj_ = view_proj; }
    /** Extra instances of the scene with these model matrices after the spinning centrepiece. */
    void set_props(std::vector<glm::mat4> models) { props_ = std::move(models); }
    /** Puts the character's feet at feet (on the y = 0 physics floor), facing yaw (+z turned about +y), posed by state; hidden, it only casts its shadow. */
    void set_character(glm::vec3 feet, float yaw, const Locomotion& state, bool visible);
    const DrawStats& draw_stats() const { return stats_; }
    /** With false nothing casts: the shadow map is only cleared, so every pixel is lit. */
    void set_shadows(bool on) { shadows_ = on; }
    /** Scales the HDR image by 2^ev before the tonemap. */
    void set_exposure(float ev) { post_.set_exposure(ev); }
    /** FXAA 3.11 on the tonemapped frame (default on). */
    void set_fxaa(bool on) { post_.set_fxaa(on); }

private:
    static constexpr uint32_t kFramesInFlight = 2;

    struct Frame {
        VkCommandPool pool = VK_NULL_HANDLE;
        VkCommandBuffer cmd = VK_NULL_HANDLE;
        VkFence in_flight = VK_NULL_HANDLE;
        VkSemaphore image_acquired = VK_NULL_HANDLE;
        Buffer block;
        VkDescriptorSet set = VK_NULL_HANDLE;
    };

    void record(VkCommandBuffer cmd, uint32_t image_index, const VkClearColorValue& color, float seconds);
    void create_present_semaphores();
    void destroy_present_semaphores();
    void recreate_swapchain();
    void record_capture(VkCommandBuffer cmd, VkImage image);
    void save_capture(VkFence done);
    struct Material {
        std::array<Texture, 3> textures{};
        Buffer block;
        VkDescriptorSet set = VK_NULL_HANDLE;
    };

    void create_materials(const std::vector<MaterialData>& materials, size_t first_character_material);
    void create_frame_sets();
    glm::mat4 fit_light(const std::vector<glm::mat4>& models) const;
    void record_shadow_pass(VkCommandBuffer cmd, const glm::mat4& light, const std::vector<glm::mat4>& models);
    bool draw(VkCommandBuffer cmd, const glm::mat4& view_proj, const glm::mat4& model, const DrawData& d,
              VkDescriptorSet* bound);
    void draw_instance(VkCommandBuffer cmd, const glm::mat4& view_proj, const glm::mat4& model, int lod,
                       VkDescriptorSet* bound);

    GpuContext& gpu_;
    std::array<Frame, kFramesInFlight> frames_{};
    GpuTimer timer_;
    VkDescriptorSetLayout set_layout_ = VK_NULL_HANDLE;
    VkDescriptorSetLayout frame_layout_ = VK_NULL_HANDLE;
    MeshPipeline pipeline_;
    DepthImage depth_;
    ColorImage hdr_;
    PostChain post_;
    Ibl ibl_;
    DepthImage shadow_map_;
    VkSampler shadow_sampler_ = VK_NULL_HANDLE;
    VkImageLayout shadow_layout_ = VK_IMAGE_LAYOUT_UNDEFINED;
    bool shadows_ = true;
    Buffer mesh_;
    VkDeviceSize index_offset_ = 0;
    std::vector<std::vector<DrawData>> lods_;
    float radius_ = 1.0f;
    DrawData ground_;
    std::array<Texture, 3> fallbacks_{};
    std::vector<Material> materials_;
    std::optional<SkinnedDraw> skinned_;
    std::vector<VkDescriptorSet> character_sets_;
    glm::mat4 character_fit_{1.0f};  // bind-pose bounds to kCharacterHeight, feet at the origin
    glm::mat4 character_model_{1.0f};
    float lift_ = 0.0f;  // raises the centrepiece so its lowest point rests on the y = 0 ground
    Locomotion locomotion_;
    bool character_visible_ = true;
    VkSampler sampler_ = VK_NULL_HANDLE;
    VkDescriptorPool descriptor_pool_ = VK_NULL_HANDLE;
    std::vector<int> instance_lods_;
    DrawStats stats_;
    std::optional<double> gpu_ms_;
    std::array<std::optional<double>, kGpuPasses> pass_ms_{};
    uint64_t blocked_ns_ = 0;
    std::vector<VkSemaphore> render_done_;
    uint32_t frame_ = 0;
    std::string capture_path_;
    std::optional<glm::mat4> view_proj_;
    std::vector<glm::mat4> props_;
    Buffer capture_buffer_;
};
