#define CGLTF_IMPLEMENTATION
#include "mesh.hpp"

#include <cgltf.h>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <mikktspace.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <memory>
#include <optional>
#include <span>
#include <string_view>
#include <stdexcept>

namespace {

SceneData cube() {
    SceneData scene{.radius = std::sqrt(0.75f), .source = "cube"};
    const float n[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
    for (const auto& f : n) {
        glm::vec3 normal(f[0], f[1], f[2]);
        glm::vec3 u = std::abs(normal.y) > 0.5f ? glm::vec3(1, 0, 0) : glm::vec3(0, 1, 0);
        glm::vec3 v = glm::cross(normal, u);
        auto base = static_cast<uint32_t>(scene.vertices.size());
        for (glm::vec2 c : {glm::vec2(-1, -1), glm::vec2(1, -1), glm::vec2(1, 1), glm::vec2(-1, 1)}) {
            glm::vec3 p = 0.5f * (normal + c.x * u + c.y * v);
            scene.vertices.push_back({{p.x, p.y, p.z}, {normal.x, normal.y, normal.z}, {0.5f * (c.x + 1), 0.5f * (1 - c.y)},
                                      {u.x, u.y, u.z, 1.0f}});
        }
        for (uint32_t i : {0u, 1u, 2u, 0u, 2u, 3u}) scene.indices.push_back(base + i);
    }
    scene.materials.emplace_back();
    scene.lods.push_back({{.index_count = static_cast<uint32_t>(scene.indices.size()), .lo = glm::vec3(-0.5f),
                           .hi = glm::vec3(0.5f)}});
    return scene;
}

/** MikkTSpace tangents for an unwelded triangle list (one vertex per corner). */
void generate_tangents(std::span<Vertex> corners) {
    SMikkTSpaceInterface iface{};
    iface.m_getNumFaces = [](const SMikkTSpaceContext* ctx) {
        return static_cast<int>(static_cast<std::span<Vertex>*>(ctx->m_pUserData)->size() / 3);
    };
    iface.m_getNumVerticesOfFace = [](const SMikkTSpaceContext*, int) { return 3; };
    iface.m_getPosition = [](const SMikkTSpaceContext* ctx, float out[], int face, int vert) {
        std::copy_n((*static_cast<std::span<Vertex>*>(ctx->m_pUserData))[face * 3 + vert].position, 3, out);
    };
    iface.m_getNormal = [](const SMikkTSpaceContext* ctx, float out[], int face, int vert) {
        std::copy_n((*static_cast<std::span<Vertex>*>(ctx->m_pUserData))[face * 3 + vert].normal, 3, out);
    };
    iface.m_getTexCoord = [](const SMikkTSpaceContext* ctx, float out[], int face, int vert) {
        std::copy_n((*static_cast<std::span<Vertex>*>(ctx->m_pUserData))[face * 3 + vert].uv, 2, out);
    };
    iface.m_setTSpaceBasic = [](const SMikkTSpaceContext* ctx, const float t[], float sign, int face, int vert) {
        float* out = (*static_cast<std::span<Vertex>*>(ctx->m_pUserData))[face * 3 + vert].tangent;
        std::copy_n(t, 3, out);
        out[3] = sign;
    };
    SMikkTSpaceContext ctx{&iface, &corners};
    genTangSpaceDefault(&ctx);
}

/** Appends a triangle primitive in its local space (with JOINTS_0/WEIGHTS_0 into scene.skin, offset by joint_base, when skinned); the draw has its index range and AABB, nothing for other primitives. */
std::optional<DrawData> append_primitive(SceneData& scene, const cgltf_primitive& prim, bool skinned = false,
                                         uint16_t joint_base = 0) {
    if (prim.type != cgltf_primitive_type_triangles) return std::nullopt;
    const cgltf_accessor* pos = nullptr;
    const cgltf_accessor* nrm = nullptr;
    const cgltf_accessor* uv = nullptr;
    const cgltf_accessor* tan = nullptr;
    const cgltf_accessor* joints = nullptr;
    const cgltf_accessor* weights = nullptr;
    for (cgltf_size i = 0; i < prim.attributes_count; i++) {
        const cgltf_attribute& a = prim.attributes[i];
        if (a.type == cgltf_attribute_type_position) pos = a.data;
        if (a.type == cgltf_attribute_type_normal) nrm = a.data;
        if (a.type == cgltf_attribute_type_texcoord && a.index == 0) uv = a.data;
        if (a.type == cgltf_attribute_type_tangent) tan = a.data;
        if (a.type == cgltf_attribute_type_joints && a.index == 0) joints = a.data;
        if (a.type == cgltf_attribute_type_weights && a.index == 0) weights = a.data;
    }
    if (!pos || pos->count == 0) return std::nullopt;
    std::vector<Vertex> verts(pos->count);
    std::vector<SkinVertex> skin(skinned ? pos->count : 0);
    for (cgltf_size i = 0; i < skin.size(); i++) {
        cgltf_uint j[4] = {};
        if (joints) cgltf_accessor_read_uint(joints, i, j, 4);
        if (weights) cgltf_accessor_read_float(weights, i, skin[i].weights, 4);
        for (int k = 0; k < 4; k++) skin[i].joints[k] = static_cast<uint16_t>(joint_base + j[k]);
    }
    DrawData draw{.first_index = static_cast<uint32_t>(scene.indices.size()), .lo = glm::vec3(1e30f), .hi = glm::vec3(-1e30f)};
    for (cgltf_size i = 0; i < pos->count; i++) {
        glm::vec3 p(0.0f), n(0.0f, 1.0f, 0.0f);
        glm::vec2 t(0.0f);
        glm::vec4 tg(1.0f, 0.0f, 0.0f, 1.0f);
        cgltf_accessor_read_float(pos, i, glm::value_ptr(p), 3);
        if (nrm) cgltf_accessor_read_float(nrm, i, glm::value_ptr(n), 3);
        if (uv) cgltf_accessor_read_float(uv, i, glm::value_ptr(t), 2);
        if (tan) cgltf_accessor_read_float(tan, i, glm::value_ptr(tg), 4);
        draw.lo = glm::min(draw.lo, p);
        draw.hi = glm::max(draw.hi, p);
        verts[i] = {{p.x, p.y, p.z}, {n.x, n.y, n.z}, {t.x, t.y}, {tg.x, tg.y, tg.z, tg.w}};
    }
    std::vector<uint32_t> idx;
    if (prim.indices) {
        for (cgltf_size i = 0; i < prim.indices->count; i++)
            idx.push_back(static_cast<uint32_t>(cgltf_accessor_read_index(prim.indices, i)));
    } else {
        for (cgltf_size i = 0; i < pos->count; i++) idx.push_back(static_cast<uint32_t>(i));
    }
    const auto base = static_cast<uint32_t>(scene.vertices.size());
    if (!tan && uv) {
        std::vector<Vertex> corners;
        corners.reserve(idx.size());
        for (uint32_t i : idx) corners.push_back(verts[i]);
        generate_tangents(corners);
        scene.vertices.insert(scene.vertices.end(), corners.begin(), corners.end());
        if (skinned)
            for (uint32_t i : idx) scene.skin.push_back(skin[i]);
        for (uint32_t i = 0; i < corners.size(); i++) scene.indices.push_back(base + i);
    } else {
        scene.vertices.insert(scene.vertices.end(), verts.begin(), verts.end());
        scene.skin.insert(scene.skin.end(), skin.begin(), skin.end());
        for (uint32_t i : idx) scene.indices.push_back(base + i);
    }
    draw.index_count = static_cast<uint32_t>(scene.indices.size()) - draw.first_index;
    return draw;
}

/** KTX2 bytes of a KHR_texture_basisu texture (buffer view or file uri); empty for any other image. */
std::vector<uint8_t> ktx2_bytes(const cgltf_texture* tex, const std::filesystem::path& dir) {
    if (!tex || !tex->has_basisu || !tex->basisu_image) return {};
    const cgltf_image& img = *tex->basisu_image;
    if (img.buffer_view) {
        const auto* p = static_cast<const uint8_t*>(cgltf_buffer_view_data(img.buffer_view));
        return p ? std::vector<uint8_t>(p, p + img.buffer_view->size) : std::vector<uint8_t>{};
    }
    if (!img.uri || std::string_view(img.uri).starts_with("data:")) return {};
    std::string uri = img.uri;
    cgltf_decode_uri(uri.data());
    std::ifstream in(dir / uri.c_str(), std::ios::binary);
    return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}

MaterialData load_material(const cgltf_material& m, const std::filesystem::path& dir) {
    MaterialData out;
    const cgltf_pbr_metallic_roughness& pbr = m.pbr_metallic_roughness;
    std::copy_n(pbr.base_color_factor, 4, out.base_color_factor);
    out.metallic = pbr.metallic_factor;
    out.roughness = pbr.roughness_factor;
    out.base_color = ktx2_bytes(pbr.base_color_texture.texture, dir);
    out.normal = ktx2_bytes(m.normal_texture.texture, dir);
    out.normal_scale = m.normal_texture.texture ? m.normal_texture.scale : 1.0f;
    out.orm = ktx2_bytes(pbr.metallic_roughness_texture.texture, dir);
    const cgltf_texture* mr = pbr.metallic_roughness_texture.texture;
    const cgltf_texture* ao = m.occlusion_texture.texture;
    const bool packed = mr && ao && mr->basisu_image == ao->basisu_image;
    out.occlusion_strength = packed ? m.occlusion_texture.scale : 0.0f;
    return out;
}

/** Index of an equal material already in the scene (LODs share their KTX2 bytes), else appends it. */
uint32_t add_material(SceneData& scene, MaterialData material) {
    const auto it = std::find(scene.materials.begin(), scene.materials.end(), material);
    if (it != scene.materials.end()) return static_cast<uint32_t>(it - scene.materials.begin());
    scene.materials.push_back(std::move(material));
    return static_cast<uint32_t>(scene.materials.size() - 1);
}

/** Appends one glTF file as a LOD: a draw per node and triangle primitive; a mesh shared by nodes is stored once. */
void append_lod(SceneData& scene, const std::string& path) {
    cgltf_options options{};
    cgltf_data* raw = nullptr;
    if (cgltf_parse_file(&options, path.c_str(), &raw) != cgltf_result_success)
        throw std::runtime_error("glTF parse: " + path);
    std::unique_ptr<cgltf_data, decltype(&cgltf_free)> data(raw, cgltf_free);
    if (cgltf_load_buffers(&options, data.get(), path.c_str()) != cgltf_result_success)
        throw std::runtime_error("glTF buffers: " + path);

    const std::filesystem::path dir = std::filesystem::path(path).parent_path();
    std::map<const cgltf_primitive*, std::optional<DrawData>> geometry;
    std::map<const cgltf_material*, uint32_t> materials;
    std::vector<DrawData>& draws = scene.lods.emplace_back();
    for (cgltf_size i = 0; i < data->nodes_count; i++) {
        const cgltf_node& node = data->nodes[i];
        if (!node.mesh) continue;
        glm::mat4 world;
        cgltf_node_transform_world(&node, glm::value_ptr(world));
        for (cgltf_size p = 0; p < node.mesh->primitives_count; p++) {
            const cgltf_primitive& prim = node.mesh->primitives[p];
            auto [slot, added] = geometry.try_emplace(&prim);
            if (added) slot->second = append_primitive(scene, prim);
            if (!slot->second) continue;
            auto [mat, fresh] = materials.try_emplace(prim.material);
            if (fresh) mat->second = add_material(scene, prim.material ? load_material(*prim.material, dir) : MaterialData{});
            DrawData draw = *slot->second;
            draw.material = mat->second;
            draw.transform = world;
            draws.push_back(draw);
        }
    }
    if (draws.empty()) throw std::runtime_error("glTF has no triangles: " + path);
}

/** Root transform that centres LOD 0 on the origin with unit radius. */
glm::mat4 unit_sphere_root(const SceneData& scene) {
    glm::vec3 lo(1e30f), hi(-1e30f);
    std::vector<glm::vec3> points;
    for (const DrawData& d : scene.lods[0]) {
        for (uint32_t i = d.first_index; i < d.first_index + d.index_count; i++) {
            const glm::vec3 p(d.transform * glm::vec4(glm::make_vec3(scene.vertices[scene.indices[i]].position), 1.0f));
            lo = glm::min(lo, p);
            hi = glm::max(hi, p);
            points.push_back(p);
        }
    }
    const glm::vec3 centre = 0.5f * (lo + hi);
    float radius = 0.0f;
    for (const glm::vec3& p : points) radius = std::max(radius, glm::length(p - centre));
    if (radius <= 0.0f) return glm::mat4(1.0f);
    return glm::scale(glm::mat4(1.0f), glm::vec3(1.0f / radius)) * glm::translate(glm::mat4(1.0f), -centre);
}

}  // namespace

void append_skinned(SceneData& scene, const cgltf_data& data, const std::string& path,
                    const std::vector<uint16_t>& joint_base) {
    const std::filesystem::path dir = std::filesystem::path(path).parent_path();
    std::map<const cgltf_material*, uint32_t> materials;
    std::vector<DrawData>& draws = scene.lods.emplace_back();
    for (cgltf_size i = 0; i < data.nodes_count; i++) {
        const cgltf_node& node = data.nodes[i];
        if (!node.mesh || !node.skin) continue;
        const uint16_t base = joint_base[cgltf_skin_index(&data, node.skin)];
        for (cgltf_size p = 0; p < node.mesh->primitives_count; p++) {
            const cgltf_primitive& prim = node.mesh->primitives[p];
            std::optional<DrawData> draw = append_primitive(scene, prim, true, base);
            if (!draw) continue;
            auto [mat, fresh] = materials.try_emplace(prim.material);
            if (fresh) mat->second = add_material(scene, prim.material ? load_material(*prim.material, dir) : MaterialData{});
            draw->material = mat->second;
            draws.push_back(*draw);
        }
    }
    if (draws.empty()) throw std::runtime_error("glTF has no skinned triangles: " + path);
}

SceneData load_scene(const std::string& path) {
    if (!std::filesystem::exists(path)) return cube();
    SceneData scene{.source = path};
    append_lod(scene, path);
    const std::string name = std::filesystem::path(path).filename().string();
    if (const auto at = name.rfind("lod0"); at != std::string::npos) {
        for (char n : {'1', '2'}) {
            std::string sibling = name;
            sibling[at + 3] = n;
            const std::filesystem::path p = std::filesystem::path(path).parent_path() / sibling;
            if (!std::filesystem::exists(p)) break;
            append_lod(scene, p.string());
        }
    }
    const glm::mat4 root = unit_sphere_root(scene);
    for (auto& lod : scene.lods)
        for (DrawData& d : lod) d.transform = root * d.transform;
    return scene;
}

float lowest_y(const std::vector<DrawData>& draws) {
    float y = 0.0f;
    for (const DrawData& d : draws)
        for (uint32_t i = 0; i < 8; i++)
            y = std::min(y, (d.transform * glm::vec4(i & 1 ? d.hi.x : d.lo.x, i & 2 ? d.hi.y : d.lo.y,
                                                      i & 4 ? d.hi.z : d.lo.z, 1.0f)).y);
    return y;
}
