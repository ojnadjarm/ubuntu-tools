// Crossfade check for the template's animation.cpp: the pose 0.1 s into the 0.2 s idle -> walk fade against an independent 50/50 per-joint blend; an absent clip is the rest pose.
#define CGLTF_IMPLEMENTATION
#include <cgltf.h>

#include "animation.hpp"

#include <cstdio>

void append_skinned(SceneData&, const cgltf_data&, const std::string&, const std::vector<uint16_t>&) {}

namespace {

float max_diff(const std::vector<glm::mat4>& a, const std::vector<glm::mat4>& b) {
    float d = 0.0f;
    for (size_t j = 0; j < a.size(); j++)
        for (int c = 0; c < 4; c++)
            for (int r = 0; r < 4; r++) d = std::max(d, std::abs(a[j][c][r] - b[j][c][r]));
    return d;
}

}  // namespace

int main(int argc, char** argv) {
    const SkinnedModel model = load_skinned(argv[1]);
    const float dt = 1.0f / 60.0f;
    Locomotion state;
    for (int i = 0; i < 30; i++) state.advance(0.0f, dt);
    state.advance(1.0f, dt);  // the switch to walk
    for (int i = 0; i < 6; i++) state.advance(1.0f, dt);
    const std::vector<glm::mat4> got = sample_pose(model, state);
    const float weight = state.weight();

    std::vector<SkeletonNode> idle = sample_local(model, model.clips[0], state.time[0]);
    const std::vector<SkeletonNode> walk = sample_local(model, model.clips[1], state.time[1]);
    std::vector<SkeletonNode> half = idle;
    for (size_t i = 0; i < half.size(); i++) {
        const glm::quat a = idle[i].rotation, b = glm::dot(a, walk[i].rotation) < 0.0f ? -walk[i].rotation : walk[i].rotation;
        half[i].translation = 0.5f * (idle[i].translation + walk[i].translation);
        half[i].rotation = glm::normalize(a + b);
        half[i].scale = 0.5f * (idle[i].scale + walk[i].scale);
    }
    const float err = max_diff(got, joint_matrices(model, half));
    const float vs_idle = max_diff(got, joint_matrices(model, idle));
    for (int i = 0; i < 6; i++) state.advance(1.0f, dt);
    const float end = max_diff(sample_pose(model, state), joint_matrices(model, sample_local(model, model.clips[1], state.time[1])));
    const float rest = max_diff(joint_matrices(model, sample_local(model, AnimClip{}, 0.3f)), joint_matrices(model, model.nodes));
    std::printf("BLEND weight=%.6f max_err=%.3g vs_idle=%.3g end_err=%.3g rest_err=%.3g\n", weight, err, vs_idle, end, rest);
    return !(std::abs(weight - 0.5f) <= 1e-4f && err <= 1e-4f && vs_idle > 1e-3f && end <= 1e-6f && rest == 0.0f);
}
