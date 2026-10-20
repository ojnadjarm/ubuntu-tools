#pragma once

#include "animation.hpp"
#include "audio.hpp"
#include "camera.hpp"
#include "input.hpp"
#include "mesh.hpp"
#include "physics.hpp"

#include <glm/gtc/constants.hpp>

#include <array>
#include <vector>

/** Arena game state on a fixed 60 Hz step: walk the floor (Jolt collision with the walls and the turntable scene), collect 3 pickups, then reach the goal; owns the sound. */
class Game {
public:
    static constexpr float kDt = 1.0f / 60.0f;

    explicit Game(const SceneData& scene, AudioOut audio_out = AudioOut::off, const std::string& wav_path = {});

    void tick(const Actions& a);
    /** The first-person eye (yaw and pitch also aim the third-person arm). */
    const FpsCamera& camera() const { return camera_; }
    /** Spring arm behind the character: kArm long, shortened by a Jolt ray so it stops short of the floor and the turntable. */
    FpsCamera third_person() const;
    glm::vec3 feet() const { return physics_.feet(); }
    /** Character heading: +z turned about +y, toward the walk direction. */
    float facing() const { return facing_; }
    const Locomotion& locomotion() const { return locomotion_; }
    long ticks() const { return tick_; }
    long win_tick() const { return win_tick_; }
    int collected() const;
    /** Model matrices of the pickups still in play and the goal pillar. */
    std::vector<glm::mat4> props() const;

private:
    struct Pickup {
        glm::vec3 position;
        bool taken = false;
    };

    FpsCamera camera_;
    Physics physics_;
    std::array<Pickup, 3> pickups_{{{{0.0f, 0.3f, 3.3f}}, {{-3.0f, 0.3f, 2.0f}}, {{3.0f, 0.3f, -0.5f}}}};
    glm::vec3 goal_{2.8f, 0.0f, 3.2f};
    long tick_ = 0;
    long win_tick_ = -1;
    float stride_ = 0.0f;
    float facing_ = glm::pi<float>();
    Locomotion locomotion_;
    Audio audio_;
};
