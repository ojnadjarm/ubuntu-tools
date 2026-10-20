#pragma once

#include "mesh.hpp"

#include <glm/glm.hpp>

#include <memory>

/** Jolt world on the game's fixed step: floor at y = 0, arena walls, LOD 0 of the scene as a turntable mesh resting on the floor, and a CharacterVirtual capsule for the player. */
class Physics {
public:
    Physics(const SceneData& scene, float arena_half, glm::vec3 feet);
    ~Physics();
    Physics(const Physics&) = delete;
    Physics& operator=(const Physics&) = delete;

    /** One step: turns the scene to turntable_angle about +y, then walks the player (gravity, jump when grounded, step-up, slope limit). */
    void step(glm::vec3 walk_velocity, float jump_speed, float turntable_angle, float dt);
    glm::vec3 feet() const;
    /** Fraction 0..1 of the segment from..to before the floor or the turntable (1 when clear; the invisible arena walls and the player are skipped). */
    float ray(glm::vec3 from, glm::vec3 to) const;
    bool grounded() const;

private:
    struct World;
    std::unique_ptr<World> world_;
};
