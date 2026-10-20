#pragma once

#include <glm/glm.hpp>

#include <cstdint>
#include <string>
#include <vector>

struct Vertex {
    float position[3];
    float normal[3];
    float uv[2];
    float tangent[4];
};

/** Second vertex stream of a skinned mesh: up to 4 joint indices (into the model's joint list) and their weights. */
struct SkinVertex {
    uint16_t joints[4];
    float weights[4];
};

/** glTF metallic-roughness material: KTX2 bytes per map (empty when absent) and the factors they scale. */
struct MaterialData {
    std::vector<uint8_t> base_color, normal, orm;
    float base_color_factor[4] = {0.85f, 0.62f, 0.38f, 1.0f};
    float metallic = 0.0f;
    float roughness = 0.5f;
    float normal_scale = 1.0f;
    float occlusion_strength = 1.0f;

    bool operator==(const MaterialData&) const = default;
};

/** One draw of a node's primitive: absolute index range, material index, node transform and local AABB. */
struct DrawData {
    uint32_t first_index = 0;
    uint32_t index_count = 0;
    uint32_t material = 0;
    glm::mat4 transform{1.0f};
    glm::vec3 lo{0.0f}, hi{0.0f};
};

/** Every LOD of a model in one vertex/index list; lods[n] holds the draws of LOD n, all inside a sphere of radius at the origin. */
struct SceneData {
    std::vector<Vertex> vertices;
    std::vector<SkinVertex> skin;  // parallel to vertices for a skinned mesh, else empty
    std::vector<uint32_t> indices;
    std::vector<MaterialData> materials;
    std::vector<std::vector<DrawData>> lods;
    float radius = 1.0f;
    std::string source;
};

struct cgltf_data;

/** Appends every skinned node's triangle primitives as one LOD in bind pose (node transforms ignored, as glTF skinning does); skin s's joint indices are offset by joint_base[s]. */
void append_skinned(SceneData& scene, const cgltf_data& data, const std::string& path, const std::vector<uint16_t>& joint_base);

/** Loads a glTF/glb scene plus its model_lod1/2 siblings, scaled by LOD 0 to the unit sphere; a unit cube when the file does not exist. */
SceneData load_scene(const std::string& path);
/** Lowest world y of the draws' AABBs, at most 0. */
float lowest_y(const std::vector<DrawData>& draws);
