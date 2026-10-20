#include "game.hpp"

#include <glm/gtc/matrix_transform.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace {

constexpr float kEyeHeight = 0.8f;
constexpr float kArenaHalf = 3.5f;
constexpr float kWalkSpeed = 3.0f;
constexpr float kJumpSpeed = 4.0f;
constexpr float kTurntableSpin = 0.5f;  // rad/s, as the renderer spins the scene model
constexpr float kPickupRadius = 0.5f;
constexpr float kGoalRadius = 0.6f;
constexpr float kStrideLength = 0.6f;
constexpr float kTurnRate = 10.0f;     // rad/s the body turns toward the walk direction
constexpr float kArmPivot = 0.8f;      // above the feet
constexpr float kArm = 2.0f;
constexpr float kArmMargin = 0.2f;     // kept from a hit, twice the near plane

float flat_distance(glm::vec3 a, glm::vec3 b) { return std::hypot(a.x - b.x, a.z - b.z); }

}  // namespace

Game::Game(const SceneData& scene, AudioOut audio_out, const std::string& wav_path)
    : physics_(scene, kArenaHalf, camera_.position - glm::vec3(0.0f, kEyeHeight, 0.0f)), audio_(audio_out, wav_path) {}

int Game::collected() const {
    return static_cast<int>(std::count_if(pickups_.begin(), pickups_.end(), [](const Pickup& p) { return p.taken; }));
}

void Game::tick(const Actions& a) {
    tick_++;
    FpsCamera& c = camera_;
    c.yaw = std::remainder(c.yaw + a.look_yaw, 2.0f * glm::pi<float>());
    c.pitch = std::clamp(c.pitch + a.look_pitch, -1.5f, 1.5f);

    glm::vec3 move = c.flat_forward() * a.move_z + c.flat_right() * a.move_x;
    if (glm::length(move) > 1.0f) move = glm::normalize(move);
    const glm::vec3 before = c.position;
    const bool grounded = physics_.grounded();
    physics_.step(move * kWalkSpeed, a.jump ? kJumpSpeed : 0.0f, kTurntableSpin * tick_ * kDt, kDt);
    c.position = physics_.feet() + glm::vec3(0.0f, kEyeHeight, 0.0f);
    audio_.set_listener(c.position, c.forward());
    const float speed = flat_distance(before, c.position) / kDt;
    locomotion_.advance(speed, kDt);
    if (speed >= Locomotion::kWalkSpeed) {
        const float turn = std::remainder(std::atan2(c.position.x - before.x, c.position.z - before.z) - facing_,
                                          2.0f * glm::pi<float>());
        facing_ = std::remainder(facing_ + std::clamp(turn, -kTurnRate * kDt, kTurnRate * kDt), 2.0f * glm::pi<float>());
    }
    if (grounded) stride_ += flat_distance(before, c.position);
    if (stride_ >= kStrideLength) {
        stride_ -= kStrideLength;
        audio_.play(Sfx::step);
    }

    for (Pickup& p : pickups_) {
        if (p.taken || flat_distance(c.position, p.position) > kPickupRadius) continue;
        p.taken = true;
        audio_.play(Sfx::pickup, p.position);
        std::printf("GAME pickup n=%d tick=%ld\n", collected(), tick_);
    }
    if (win_tick_ < 0 && collected() == 3 && flat_distance(c.position, goal_) <= kGoalRadius) {
        win_tick_ = tick_;
        audio_.play(Sfx::goal, goal_ + glm::vec3(0.0f, 1.0f, 0.0f));
        std::printf("GAME win t=%.3f tick=%ld\n", tick_ * kDt, tick_);
    }
    audio_.end_tick(kDt);
}

FpsCamera Game::third_person() const {
    const glm::vec3 pivot = physics_.feet() + glm::vec3(0.0f, kArmPivot, 0.0f);
    const float reach = kArm + kArmMargin;
    const float hit = physics_.ray(pivot, pivot - camera_.forward() * reach) * reach;
    return camera_.behind(pivot, std::max(hit - kArmMargin, 0.0f));
}

std::vector<glm::mat4> Game::props() const {
    const float t = tick_ * kDt;
    std::vector<glm::mat4> models;
    for (size_t i = 0; i < pickups_.size(); i++) {
        if (pickups_[i].taken) continue;
        const glm::vec3 bob(0.0f, 0.1f * std::sin(2.0f * t + float(i)), 0.0f);
        glm::mat4 m = glm::translate(glm::mat4(1.0f), pickups_[i].position + bob);
        m = glm::rotate(m, 2.0f * t, glm::vec3(0.3f, 1.0f, 0.0f));
        models.push_back(glm::scale(m, glm::vec3(0.25f)));
    }
    const float spin = win_tick_ < 0 ? 0.0f : 3.0f * (tick_ - win_tick_) * kDt;
    glm::mat4 goal = glm::translate(glm::mat4(1.0f), goal_ + glm::vec3(0.0f, 1.0f, 0.0f));
    goal = glm::rotate(goal, spin, glm::vec3(0.0f, 1.0f, 0.0f));
    models.push_back(glm::scale(goal, glm::vec3(0.3f, 2.0f, 0.3f)));
    return models;
}
