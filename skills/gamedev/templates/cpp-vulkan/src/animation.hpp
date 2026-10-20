#pragma once

#include "mesh.hpp"

#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>

#include <algorithm>
#include <array>
#include <optional>
#include <string>
#include <vector>

/** A glTF node's parent and rest transform (TRS, or a fixed matrix that animation never targets). */
struct SkeletonNode {
    int parent = -1;
    glm::vec3 translation{0.0f};
    glm::quat rotation{1.0f, 0.0f, 0.0f, 0.0f};
    glm::vec3 scale{1.0f};
    std::optional<glm::mat4> matrix;
};

/** Keyframes of one node property; values are xyz (translation, scale) or xyzw (rotation). */
struct AnimChannel {
    enum class Path : uint8_t { Translation, Rotation, Scale };
    uint32_t node = 0;
    Path path = Path::Translation;
    bool step = false;
    std::vector<float> times;
    std::vector<glm::vec4> values;
};

struct AnimClip {
    std::string name;
    float duration = 0.0f;
    std::vector<AnimChannel> channels;
};

/** The locomotion clips, in SkinnedModel::clips order. */
enum class Clip : uint8_t { Idle, Walk };

/** An animated glTF character: bind-pose geometry with joint streams, the node tree, every skin's joints (concatenated) and the idle and walk clips (empty, the rest pose, when absent). */
struct SkinnedModel {
    SceneData mesh;
    std::vector<SkeletonNode> nodes;
    std::vector<uint32_t> order;  // parents before children
    std::vector<uint32_t> joint_nodes;
    std::vector<glm::mat4> inverse_bind;
    std::array<AnimClip, 2> clips;
    glm::vec3 lo{0.0f}, hi{0.0f};  // bind-pose bounds
};

/** Idle/walk state on the game's fixed step: walk at horizontal speed >= kWalkSpeed, a kFade crossfade on each switch, every clip's clock running. */
struct Locomotion {
    static constexpr float kWalkSpeed = 0.1f;
    static constexpr float kFade = 0.2f;
    Clip current = Clip::Idle;
    Clip previous = Clip::Idle;
    float fade = kFade;  // seconds since the switch
    std::array<float, 2> time{};

    void advance(float speed, float dt);
    /** Weight of current against previous, 0..1. */
    float weight() const { return std::min(fade / kFade, 1.0f); }
};

/** Loads the skinned meshes of a glTF/glb and its "idle" and "walk" animations; throws without a skin. */
SkinnedModel load_skinned(const std::string& path);

/** Local TRS of every node for clip at seconds, looped: LERP for translation and scale, SLERP for rotation. */
std::vector<SkeletonNode> sample_local(const SkinnedModel& model, const AnimClip& clip, float seconds);

/** Per-node LERP of translation and scale, SLERP of rotation: w = 0 gives a, 1 gives b. */
std::vector<SkeletonNode> blend(std::vector<SkeletonNode> a, const std::vector<SkeletonNode>& b, float w);

/** Joint matrices in model space for a local pose. */
std::vector<glm::mat4> joint_matrices(const SkinnedModel& model, const std::vector<SkeletonNode>& local);

/** Joint matrices of the locomotion state: the previous clip crossfaded into the current one. */
std::vector<glm::mat4> sample_pose(const SkinnedModel& model, const Locomotion& state);
