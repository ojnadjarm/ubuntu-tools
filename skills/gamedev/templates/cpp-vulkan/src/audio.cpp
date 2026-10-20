#include "audio.hpp"

#include <miniaudio.h>

#include <array>
#include <cmath>
#include <list>
#include <stdexcept>
#include <vector>

namespace {

constexpr ma_uint32 kRate = 48000;
constexpr ma_uint32 kChannels = 2;
constexpr std::array<const char*, 3> kClips{"pickup.wav", "goal.wav", "step.wav"};

void check(ma_result r, const char* what) {
    if (r != MA_SUCCESS) throw std::runtime_error(std::string("audio: ") + what + ": " + ma_result_description(r));
}

}  // namespace

struct Audio::Impl {
    ma_engine engine{};
    std::array<ma_sound, kClips.size()> clips{};
    std::list<ma_sound> voices;
    ma_encoder encoder{};
    bool to_file = false;
    std::vector<float> mix;
    std::vector<ma_int16> pcm;

    Impl(AudioOut out, const std::string& wav_path) : to_file(out == AudioOut::file) {
        ma_engine_config config = ma_engine_config_init();
        config.listenerCount = 1;
        if (to_file) {
            config.noDevice = MA_TRUE;
            config.channels = kChannels;
            config.sampleRate = kRate;
        }
        check(ma_engine_init(&config, &engine), "engine");
        ma_engine_listener_set_world_up(&engine, 0, 0.0f, 1.0f, 0.0f);
        size_t loaded = 0;
        try {
            for (; loaded < kClips.size(); loaded++) {
                const std::string path = std::string(GAME_ASSET_DIR) + "/" + kClips[loaded];
                check(ma_sound_init_from_file(&engine, path.c_str(), MA_SOUND_FLAG_DECODE, nullptr, nullptr,
                                              &clips[loaded]),
                      kClips[loaded]);
            }
            if (to_file) {
                const ma_encoder_config ec = ma_encoder_config_init(ma_encoding_format_wav, ma_format_s16, kChannels, kRate);
                check(ma_encoder_init_file(wav_path.c_str(), &ec, &encoder), "wav out");
            }
        } catch (...) {
            for (size_t i = 0; i < loaded; i++) ma_sound_uninit(&clips[i]);
            ma_engine_uninit(&engine);
            throw;
        }
    }

    ~Impl() {
        for (ma_sound& v : voices) ma_sound_uninit(&v);
        for (ma_sound& c : clips) ma_sound_uninit(&c);
        if (to_file) ma_encoder_uninit(&encoder);
        ma_engine_uninit(&engine);
    }
    Impl(const Impl&) = delete;
    Impl& operator=(const Impl&) = delete;
};

Audio::Audio(AudioOut out, const std::string& wav_path)
    : impl_(out == AudioOut::off ? nullptr : std::make_unique<Impl>(out, wav_path)) {}

Audio::~Audio() = default;

void Audio::set_listener(glm::vec3 position, glm::vec3 forward) {
    if (!impl_) return;
    ma_engine_listener_set_position(&impl_->engine, 0, position.x, position.y, position.z);
    ma_engine_listener_set_direction(&impl_->engine, 0, forward.x, forward.y, forward.z);
}

void Audio::play(Sfx sfx, std::optional<glm::vec3> position) {
    if (!impl_) return;
    ma_sound& voice = impl_->voices.emplace_back();
    if (ma_sound_init_copy(&impl_->engine, &impl_->clips[static_cast<size_t>(sfx)], 0, nullptr, &voice) != MA_SUCCESS) {
        impl_->voices.pop_back();
        return;
    }
    ma_sound_set_doppler_factor(&voice, 0.0f);
    if (position) ma_sound_set_position(&voice, position->x, position->y, position->z);
    else ma_sound_set_spatialization_enabled(&voice, MA_FALSE);
    ma_sound_start(&voice);
}

void Audio::end_tick(float dt) {
    if (!impl_) return;
    Impl& a = *impl_;
    if (a.to_file) {
        const auto frames = static_cast<ma_uint64>(std::lround(dt * kRate));
        a.mix.assign(frames * kChannels, 0.0f);
        a.pcm.resize(a.mix.size());
        ma_uint64 read = 0;
        check(ma_engine_read_pcm_frames(&a.engine, a.mix.data(), frames, &read), "mix");
        ma_pcm_f32_to_s16(a.pcm.data(), a.mix.data(), a.mix.size(), ma_dither_mode_none);
        check(ma_encoder_write_pcm_frames(&a.encoder, a.pcm.data(), frames, nullptr), "wav write");
    }
    a.voices.remove_if([](ma_sound& v) {
        if (!ma_sound_at_end(&v)) return false;
        ma_sound_uninit(&v);
        return true;
    });
}
