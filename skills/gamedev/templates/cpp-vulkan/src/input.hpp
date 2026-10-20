#pragma once

#include <SDL3/SDL.h>

#include <string>
#include <vector>

/** Device-free player commands for one 60 Hz tick: unit move axes, look deltas in radians, jump. */
struct Actions {
    float move_x = 0, move_z = 0, look_yaw = 0, look_pitch = 0;
    bool jump = false;
};

/** Maps keyboard (WASD/arrows/space), relative mouse and the first gamepad to Actions. */
class Input {
public:
    explicit Input(SDL_Window* window, bool grab_mouse);
    ~Input();
    Input(const Input&) = delete;
    Input& operator=(const Input&) = delete;

    /** Handles one SDL event; returns false on quit (window close or Escape). */
    bool handle(const SDL_Event& event);
    /** Actions for one tick; mouse motion accumulated since the last call is consumed. */
    Actions sample(float dt);

private:
    SDL_Gamepad* pad_ = nullptr;
    float mouse_dx_ = 0, mouse_dy_ = 0;
};

/** Records Actions per tick and writes them as JSON, or replays a recorded file tick by tick. */
class InputTape {
public:
    static InputTape load(const std::string& path);
    void push(const Actions& a) { ticks_.push_back(a); }
    void save(const std::string& path) const;
    size_t size() const { return ticks_.size(); }
    const Actions& operator[](size_t i) const { return ticks_[i]; }

private:
    std::vector<Actions> ticks_;
};
