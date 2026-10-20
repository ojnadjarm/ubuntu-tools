#include "input.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace {

constexpr float kMouseRadPerPixel = 0.0025f;
constexpr float kStickRadPerSecond = 3.0f;
constexpr float kDeadzone = 0.15f;

float stick(SDL_Gamepad* pad, SDL_GamepadAxis axis) {
    const float v = SDL_GetGamepadAxis(pad, axis) / 32767.0f;
    return std::abs(v) < kDeadzone ? 0.0f : std::clamp(v, -1.0f, 1.0f);
}

}  // namespace

Input::Input(SDL_Window* window, bool grab_mouse) {
    if (grab_mouse) SDL_SetWindowRelativeMouseMode(window, true);
}

Input::~Input() {
    if (pad_) SDL_CloseGamepad(pad_);
}

bool Input::handle(const SDL_Event& event) {
    switch (event.type) {
        case SDL_EVENT_QUIT: return false;
        case SDL_EVENT_KEY_DOWN: return event.key.key != SDLK_ESCAPE;
        case SDL_EVENT_MOUSE_MOTION:
            mouse_dx_ += event.motion.xrel;
            mouse_dy_ += event.motion.yrel;
            break;
        case SDL_EVENT_GAMEPAD_ADDED:
            if (!pad_) pad_ = SDL_OpenGamepad(event.gdevice.which);
            break;
        case SDL_EVENT_GAMEPAD_REMOVED:
            if (pad_ && SDL_GetGamepadID(pad_) == event.gdevice.which) {
                SDL_CloseGamepad(pad_);
                pad_ = nullptr;
            }
            break;
        default: break;
    }
    return true;
}

Actions Input::sample(float dt) {
    const bool* k = SDL_GetKeyboardState(nullptr);
    Actions a;
    a.move_x = float(k[SDL_SCANCODE_D] || k[SDL_SCANCODE_RIGHT]) - float(k[SDL_SCANCODE_A] || k[SDL_SCANCODE_LEFT]);
    a.move_z = float(k[SDL_SCANCODE_W] || k[SDL_SCANCODE_UP]) - float(k[SDL_SCANCODE_S] || k[SDL_SCANCODE_DOWN]);
    a.jump = k[SDL_SCANCODE_SPACE];
    a.look_yaw = mouse_dx_ * kMouseRadPerPixel;
    a.look_pitch = -mouse_dy_ * kMouseRadPerPixel;
    mouse_dx_ = mouse_dy_ = 0;
    if (pad_) {
        a.move_x += stick(pad_, SDL_GAMEPAD_AXIS_LEFTX);
        a.move_z -= stick(pad_, SDL_GAMEPAD_AXIS_LEFTY);
        a.look_yaw += stick(pad_, SDL_GAMEPAD_AXIS_RIGHTX) * kStickRadPerSecond * dt;
        a.look_pitch -= stick(pad_, SDL_GAMEPAD_AXIS_RIGHTY) * kStickRadPerSecond * dt;
        a.jump = a.jump || SDL_GetGamepadButton(pad_, SDL_GAMEPAD_BUTTON_SOUTH);
    }
    a.move_x = std::clamp(a.move_x, -1.0f, 1.0f);
    a.move_z = std::clamp(a.move_z, -1.0f, 1.0f);
    return a;
}

InputTape InputTape::load(const std::string& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("replay: cannot read " + path);
    std::stringstream ss;
    ss << in.rdbuf();
    const std::string text = ss.str();
    const size_t start = text.find("\"ticks\"");
    if (start == std::string::npos) throw std::runtime_error("replay: no \"ticks\" in " + path);
    InputTape tape;
    const char* p = text.c_str() + text.find('[', start) + 1;
    while ((p = std::strchr(p, '['))) {
        float v[5];
        for (float& x : v) {
            while (*p == '[' || *p == ',' || *p == ' ') p++;
            char* end;
            x = std::strtof(p, &end);
            if (end == p) throw std::runtime_error("replay: bad tick in " + path);
            p = end;
        }
        tape.push({v[0], v[1], v[2], v[3], v[4] != 0});
    }
    return tape;
}

void InputTape::save(const std::string& path) const {
    FILE* f = std::fopen(path.c_str(), "w");
    if (!f) throw std::runtime_error("record: cannot write " + path);
    std::fprintf(f, "{\"tick_hz\": 60, \"fields\": [\"move_x\", \"move_z\", \"look_yaw\", \"look_pitch\", \"jump\"],\n \"ticks\": [");
    for (size_t i = 0; i < ticks_.size(); i++) {
        const Actions& a = ticks_[i];
        std::fprintf(f, "%s\n  [%.9g, %.9g, %.9g, %.9g, %d]", i ? "," : "", a.move_x, a.move_z, a.look_yaw,
                     a.look_pitch, a.jump ? 1 : 0);
    }
    std::fprintf(f, "\n]}\n");
    std::fclose(f);
}
