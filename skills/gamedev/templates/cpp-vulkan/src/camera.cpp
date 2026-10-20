#include "camera.hpp"

#include <glm/gtc/matrix_transform.hpp>

#include <cmath>

glm::vec3 FpsCamera::forward() const {
    return {std::cos(pitch) * std::sin(yaw), std::sin(pitch), -std::cos(pitch) * std::cos(yaw)};
}

glm::vec3 FpsCamera::flat_forward() const { return {std::sin(yaw), 0.0f, -std::cos(yaw)}; }

glm::vec3 FpsCamera::flat_right() const { return {std::cos(yaw), 0.0f, std::sin(yaw)}; }

glm::mat4 FpsCamera::view() const { return glm::lookAt(position, position + forward(), glm::vec3(0.0f, 1.0f, 0.0f)); }

FpsCamera FpsCamera::behind(glm::vec3 pivot, float arm) const {
    FpsCamera c = *this;
    c.position = pivot - forward() * arm;
    return c;
}

glm::mat4 FpsCamera::proj(float aspect) {
    glm::mat4 p = glm::perspectiveRH_ZO(glm::radians(45.0f), aspect, 0.1f, 10.0f);
    p[1][1] *= -1.0f;
    return p;
}
