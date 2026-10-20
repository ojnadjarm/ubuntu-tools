#include "animation.hpp"

#include <cgltf.h>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>
#include <string_view>

namespace {

std::vector<SkeletonNode> read_nodes(const cgltf_data& data) {
    std::vector<SkeletonNode> nodes(data.nodes_count);
    for (cgltf_size i = 0; i < data.nodes_count; i++) {
        const cgltf_node& n = data.nodes[i];
        SkeletonNode& out = nodes[i];
        if (n.parent) out.parent = static_cast<int>(cgltf_node_index(&data, n.parent));
        if (n.has_matrix) out.matrix = glm::make_mat4(n.matrix);
        if (n.has_translation) out.translation = glm::make_vec3(n.translation);
        if (n.has_rotation) out.rotation = glm::quat(n.rotation[3], n.rotation[0], n.rotation[1], n.rotation[2]);
        if (n.has_scale) out.scale = glm::make_vec3(n.scale);
    }
    return nodes;
}

/** Node indices with every parent ahead of its children. */
std::vector<uint32_t> parent_first(const std::vector<SkeletonNode>& nodes) {
    std::vector<uint32_t> order;
    for (uint32_t i = 0; i < nodes.size(); i++)
        if (nodes[i].parent < 0) order.push_back(i);
    for (size_t k = 0; k < order.size(); k++)
        for (uint32_t i = 0; i < nodes.size(); i++)
            if (nodes[i].parent == static_cast<int>(order[k])) order.push_back(i);
    return order;
}

AnimClip read_clip(const cgltf_data& data, const cgltf_animation& anim) {
    AnimClip clip{.name = anim.name ? anim.name : ""};
    for (cgltf_size c = 0; c < anim.channels_count; c++) {
        const cgltf_animation_channel& ch = anim.channels[c];
        if (!ch.target_node || ch.target_path == cgltf_animation_path_type_weights) continue;
        const cgltf_animation_sampler& s = *ch.sampler;
        AnimChannel out{.node = static_cast<uint32_t>(cgltf_node_index(&data, ch.target_node)),
                        .path = ch.target_path == cgltf_animation_path_type_rotation ? AnimChannel::Path::Rotation
                                : ch.target_path == cgltf_animation_path_type_scale  ? AnimChannel::Path::Scale
                                                                                     : AnimChannel::Path::Translation,
                        .step = s.interpolation == cgltf_interpolation_type_step};
        // Cubic spline keys store in-tangent, value, out-tangent: keep the values only.
        const cgltf_size stride = s.interpolation == cgltf_interpolation_type_cubic_spline ? 3 : 1;
        out.times.resize(s.input->count);
        out.values.resize(s.input->count, glm::vec4(0.0f));
        const cgltf_size width = out.path == AnimChannel::Path::Rotation ? 4 : 3;
        for (cgltf_size k = 0; k < s.input->count; k++) {
            cgltf_accessor_read_float(s.input, k, &out.times[k], 1);
            cgltf_accessor_read_float(s.output, k * stride + stride / 2, glm::value_ptr(out.values[k]), width);
        }
        if (!out.times.empty()) clip.duration = std::max(clip.duration, out.times.back());
        clip.channels.push_back(std::move(out));
    }
    return clip;
}

glm::vec4 sample(const AnimChannel& ch, float t) {
    const auto next = std::upper_bound(ch.times.begin(), ch.times.end(), t);
    if (next == ch.times.begin()) return ch.values.front();
    if (next == ch.times.end()) return ch.values.back();
    const auto k = static_cast<size_t>(next - ch.times.begin()) - 1;
    if (ch.step) return ch.values[k];
    const float u = (t - ch.times[k]) / (ch.times[k + 1] - ch.times[k]);
    if (ch.path != AnimChannel::Path::Rotation) return glm::mix(ch.values[k], ch.values[k + 1], u);
    const glm::vec4 a = ch.values[k], b = ch.values[k + 1];
    const glm::quat q = glm::slerp(glm::quat(a.w, a.x, a.y, a.z), glm::quat(b.w, b.x, b.y, b.z), u);
    return {q.x, q.y, q.z, q.w};
}

}  // namespace

void Locomotion::advance(float speed, float dt) {
    for (float& t : time) t += dt;
    fade += dt;
    const Clip target = speed < kWalkSpeed ? Clip::Idle : Clip::Walk;
    if (target == current) return;
    // Reversing mid-fade mirrors the weight, so the pose does not jump.
    fade = target == previous ? std::max(kFade - fade, 0.0f) : 0.0f;
    previous = current;
    current = target;
}

SkinnedModel load_skinned(const std::string& path) {
    cgltf_options options{};
    cgltf_data* raw = nullptr;
    if (cgltf_parse_file(&options, path.c_str(), &raw) != cgltf_result_success)
        throw std::runtime_error("glTF parse: " + path);
    std::unique_ptr<cgltf_data, decltype(&cgltf_free)> data(raw, cgltf_free);
    if (cgltf_load_buffers(&options, data.get(), path.c_str()) != cgltf_result_success)
        throw std::runtime_error("glTF buffers: " + path);
    if (data->skins_count == 0) throw std::runtime_error("glTF has no skin: " + path);

    SkinnedModel model{.nodes = read_nodes(*data)};
    model.order = parent_first(model.nodes);
    std::vector<uint16_t> joint_base;
    for (cgltf_size s = 0; s < data->skins_count; s++) {
        const cgltf_skin& skin = data->skins[s];
        joint_base.push_back(static_cast<uint16_t>(model.joint_nodes.size()));
        for (cgltf_size j = 0; j < skin.joints_count; j++) {
            glm::mat4 inverse_bind(1.0f);
            if (skin.inverse_bind_matrices)
                cgltf_accessor_read_float(skin.inverse_bind_matrices, j, glm::value_ptr(inverse_bind), 16);
            model.joint_nodes.push_back(static_cast<uint32_t>(cgltf_node_index(data.get(), skin.joints[j])));
            model.inverse_bind.push_back(inverse_bind);
        }
    }
    append_skinned(model.mesh, *data, path, joint_base);
    model.lo = glm::vec3(1e30f);
    model.hi = glm::vec3(-1e30f);
    for (const Vertex& v : model.mesh.vertices) {
        model.lo = glm::min(model.lo, glm::make_vec3(v.position));
        model.hi = glm::max(model.hi, glm::make_vec3(v.position));
    }
    model.mesh.source = path;
    for (cgltf_size a = 0; a < data->animations_count; a++) {
        const cgltf_animation& anim = data->animations[a];
        const std::string_view name = anim.name ? anim.name : "";
        if (name == "idle") model.clips[size_t(Clip::Idle)] = read_clip(*data, anim);
        if (name == "walk") model.clips[size_t(Clip::Walk)] = read_clip(*data, anim);
    }
    return model;
}

std::vector<SkeletonNode> sample_local(const SkinnedModel& model, const AnimClip& clip, float seconds) {
    std::vector<SkeletonNode> nodes = model.nodes;
    const float t = clip.duration > 0.0f ? std::fmod(seconds, clip.duration) : 0.0f;
    for (const AnimChannel& ch : clip.channels) {
        const glm::vec4 v = sample(ch, t);
        SkeletonNode& n = nodes[ch.node];
        switch (ch.path) {
            case AnimChannel::Path::Translation: n.translation = glm::vec3(v); break;
            case AnimChannel::Path::Rotation: n.rotation = glm::quat(v.w, v.x, v.y, v.z); break;
            case AnimChannel::Path::Scale: n.scale = glm::vec3(v); break;
        }
    }
    return nodes;
}

std::vector<SkeletonNode> blend(std::vector<SkeletonNode> a, const std::vector<SkeletonNode>& b, float w) {
    for (size_t i = 0; i < a.size(); i++) {
        a[i].translation = glm::mix(a[i].translation, b[i].translation, w);
        a[i].rotation = glm::slerp(a[i].rotation, b[i].rotation, w);
        a[i].scale = glm::mix(a[i].scale, b[i].scale, w);
    }
    return a;
}

std::vector<glm::mat4> joint_matrices(const SkinnedModel& model, const std::vector<SkeletonNode>& nodes) {
    std::vector<glm::mat4> global(nodes.size());
    for (uint32_t i : model.order) {
        const SkeletonNode& n = nodes[i];
        const glm::mat4 local = n.matrix.value_or(glm::translate(glm::mat4(1.0f), n.translation) *
                                                  glm::mat4_cast(n.rotation) * glm::scale(glm::mat4(1.0f), n.scale));
        global[i] = n.parent < 0 ? local : global[n.parent] * local;
    }
    std::vector<glm::mat4> joints(model.joint_nodes.size());
    for (size_t j = 0; j < joints.size(); j++) joints[j] = global[model.joint_nodes[j]] * model.inverse_bind[j];
    return joints;
}

std::vector<glm::mat4> sample_pose(const SkinnedModel& model, const Locomotion& state) {
    const auto local = [&](Clip c) { return sample_local(model, model.clips[size_t(c)], state.time[size_t(c)]); };
    const float w = state.weight();
    if (w >= 1.0f) return joint_matrices(model, local(state.current));
    return joint_matrices(model, blend(local(state.previous), local(state.current), w));
}
