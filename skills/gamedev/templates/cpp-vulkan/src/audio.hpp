#pragma once

#include <glm/glm.hpp>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>

/** Where the mix goes: nowhere, the default playback device, or a WAV file rendered in sim time. */
enum class AudioOut : std::uint8_t { off, device, file };

/** One-shot clips in assets/ (make-sfx.sh). */
enum class Sfx : std::uint8_t { pickup, goal, step };

/** miniaudio engine with one listener; one-shot voices are spatialized (pan + inverse-distance gain) when given a position. */
class Audio {
public:
    Audio(AudioOut out, const std::string& wav_path);
    ~Audio();
    Audio(const Audio&) = delete;
    Audio& operator=(const Audio&) = delete;

    void set_listener(glm::vec3 position, glm::vec3 forward);
    /** Starts a voice at a world position, or centred on the listener without one. */
    void play(Sfx sfx, std::optional<glm::vec3> position = std::nullopt);
    /** Ends a sim tick of dt seconds: frees finished voices; file output appends dt of mix to the WAV. */
    void end_tick(float dt);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
