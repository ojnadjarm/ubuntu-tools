#pragma once

#include <glm/glm.hpp>

#include <cmath>

/** The player's view: from the eye, or a spring arm behind the character. */
enum class CameraMode : uint8_t { First, Third };

/** First-person camera: eye position plus yaw (0 looks down -z) and pitch in radians; defaults look at the origin. */
struct FpsCamera {
    glm::vec3 position{0.0f, 0.8f, 2.6f};
    float yaw = 0.0f;
    float pitch = std::atan2(-0.8f, 2.6f);

    glm::vec3 forward() const;
    glm::vec3 flat_forward() const;
    glm::vec3 flat_right() const;
    glm::mat4 view() const;
    /** This camera moved back from pivot by arm along its view direction, still looking at pivot. */
    FpsCamera behind(glm::vec3 pivot, float arm) const;
    /** Vulkan clip space (y down, depth 0..1), 45 degree vertical FOV. */
    static glm::mat4 proj(float aspect);
};
