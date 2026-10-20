#include "animation.hpp"
#include "crash.hpp"
#include "game.hpp"
#include "gpu_context.hpp"
#include "input.hpp"
#include "mesh.hpp"
#include "profiling.hpp"
#include "renderer.hpp"
#ifdef GAME_HOT
#include "shader_watch.hpp"
#endif

#include <SDL3/SDL.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace {

struct Options {
    long frames = 0;
    bool validate = false;
    std::string model = GAME_MODEL;
    long capture_frame = -1;
    std::string capture_path;
    bool crash_test = false;
    bool shadows = true;
    bool ibl = true;
    float exposure = 0.0f;
    bool fxaa = true;
    int width = 1280, height = 720;
    std::string record_path, replay_path, capture_dir, audio_out;
    std::optional<FpsCamera> camera;
    CameraMode camera_mode = CameraMode::Third;
    bool hot = false;
    long pause_at = -1;
};

/** Per-frame GPU and CPU milliseconds with percentiles. */
struct FrameStats {
    std::vector<double> gpu_ms, cpu_ms, post_ms;
    std::array<std::vector<double>, kGpuPasses> pass_ms;

    static double percentile(std::vector<double> v, double p) {
        if (v.empty()) return NAN;
        auto nth = v.begin() + static_cast<long>(p * (v.size() - 1));
        std::nth_element(v.begin(), nth, v.end());
        return *nth;
    }
};

Options parse_args(int argc, char** argv) {
    Options opt;
#ifndef NDEBUG
    opt.validate = true;
#endif
    for (int i = 1; i < argc; i++) {
        if (std::strcmp(argv[i], "--frames") == 0 && i + 1 < argc) opt.frames = std::atol(argv[++i]);
        else if (std::strcmp(argv[i], "--validate") == 0) opt.validate = true;
        else if (std::strcmp(argv[i], "--no-validate") == 0) opt.validate = false;
        else if (std::strcmp(argv[i], "--model") == 0 && i + 1 < argc) opt.model = argv[++i];
        else if (std::strcmp(argv[i], "--capture") == 0 && i + 2 < argc) {
            opt.capture_frame = std::atol(argv[++i]);
            opt.capture_path = argv[++i];
        } else if (std::strcmp(argv[i], "--crash-test") == 0) opt.crash_test = true;
        else if (std::strcmp(argv[i], "--no-shadows") == 0) opt.shadows = false;
        else if (std::strcmp(argv[i], "--no-ibl") == 0) opt.ibl = false;
        else if (std::strcmp(argv[i], "--aa") == 0 && i + 1 < argc) opt.fxaa = std::strcmp(argv[++i], "off") != 0;
        else if (std::strcmp(argv[i], "--exposure") == 0 && i + 1 < argc) opt.exposure = std::strtof(argv[++i], nullptr);
        else if (std::strcmp(argv[i], "--size") == 0 && i + 1 < argc) std::sscanf(argv[++i], "%dx%d", &opt.width, &opt.height);
        else if (std::strcmp(argv[i], "--record") == 0 && i + 1 < argc) opt.record_path = argv[++i];
        else if (std::strcmp(argv[i], "--replay") == 0 && i + 1 < argc) opt.replay_path = argv[++i];
        else if (std::strcmp(argv[i], "--capture-every") == 0 && i + 1 < argc) opt.capture_dir = argv[++i];
        else if (std::strcmp(argv[i], "--audio-out") == 0 && i + 1 < argc) opt.audio_out = argv[++i];
        else if (std::strcmp(argv[i], "--hot") == 0) opt.hot = true;
        else if (std::strcmp(argv[i], "--pause-at") == 0 && i + 1 < argc) opt.pause_at = std::atol(argv[++i]);
        else if (std::strcmp(argv[i], "--camera") == 0 && i + 1 < argc) {
            FpsCamera c;
            if (std::strcmp(argv[++i], "first") == 0) opt.camera_mode = CameraMode::First;
            else if (std::strcmp(argv[i], "third") == 0) opt.camera_mode = CameraMode::Third;
            else if (std::sscanf(argv[i], "%f,%f,%f,%f,%f", &c.position.x, &c.position.y, &c.position.z, &c.yaw, &c.pitch) == 5)
                opt.camera = c;
        }
    }
    return opt;
}

/** Crash-handler fixture: a store through a null pointer the optimizer cannot see. */
[[gnu::noinline]] void crash_test() {
    static int* volatile target = nullptr;
    *target = 1;
}

int run(const Options& opt, SDL_Window* window) {
    const SceneData scene = load_scene(opt.model);
    std::printf("MESH source=%s vertices=%zu triangles=%zu\n", scene.source.c_str(), scene.vertices.size(),
                scene.indices.size() / 3);
    std::printf("SCENE lods=%zu materials=%zu draws_lod0=%zu\n", scene.lods.size(), scene.materials.size(),
                scene.lods[0].size());
    std::optional<SkinnedModel> character;
    if (const std::string path = std::string(GAME_ASSET_DIR) + "/character.glb"; std::filesystem::exists(path)) {
        character = load_skinned(path);
        const AnimClip &idle = character->clips[size_t(Clip::Idle)], &walk = character->clips[size_t(Clip::Walk)];
        std::printf("SKIN source=%s vertices=%zu joints=%zu idle=%.3f/%zu walk=%.3f/%zu\n", path.c_str(),
                    character->mesh.vertices.size(), character->joint_nodes.size(), idle.duration, idle.channels.size(),
                    walk.duration, walk.channels.size());
    }
    GpuContext gpu(window, opt.validate);
    Renderer renderer(gpu, scene, std::move(character), opt.ibl ? std::string(GAME_ASSET_DIR) + "/environment.hdr" : "");
    renderer.set_shadows(opt.shadows);
    renderer.set_exposure(opt.exposure);
    renderer.set_fxaa(opt.fxaa);
    std::printf("GAME device=\"%s\" video=%s present_mode=%d extent=%ux%u validate=%d\n", gpu.device_name(),
                SDL_GetCurrentVideoDriver(), gpu.present_mode(), gpu.extent().width, gpu.extent().height,
                opt.validate);

    const InputTape replay = opt.replay_path.empty() ? InputTape{} : InputTape::load(opt.replay_path);
    const bool fixed_step = opt.capture_frame >= 0 || !opt.replay_path.empty() || !opt.capture_dir.empty() ||
                            opt.pause_at >= 0;
    const bool interactive = opt.frames == 0 && !fixed_step;
    Input input(window, interactive);
#ifdef GAME_HOT
    std::optional<ShaderWatch> watch;
    if (opt.hot) watch.emplace(gpu.device());
#else
    if (opt.hot) std::printf("HOT off: only Debug builds watch shaders\n");
#endif
    InputTape record;
    Game game(scene, !opt.audio_out.empty() ? AudioOut::file : interactive ? AudioOut::device : AudioOut::off, opt.audio_out);
    double sim_lag = 0;

    const Uint64 start = SDL_GetTicksNS();
    Uint64 last = start;
    Uint64 window_start = start;
    long frames = 0, window_frames = 0;
    FrameStats stats;
    VramUsage vram_peak = gpu.vram();
    bool running = true;
    while (running && (opt.frames == 0 || frames < opt.frames)) {
        const Uint64 frame_start = SDL_GetTicksNS();
        SDL_Event event;
        while (SDL_PollEvent(&event)) running = input.handle(event) && running;
        if (SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED) {
            SDL_Delay(10);
            continue;
        }
        const bool paused = opt.pause_at >= 0 && frames >= opt.pause_at;
        if (!paused && !opt.replay_path.empty() && frames >= static_cast<long>(replay.size())) break;
        sim_lag = paused ? 0.0 : fixed_step ? Game::kDt : std::min(sim_lag + (frame_start - last) * 1e-9, 0.25);
        last = frame_start;
        for (; sim_lag >= Game::kDt * 0.999; sim_lag -= Game::kDt) {
            const Actions actions = opt.replay_path.empty() ? input.sample(Game::kDt) : replay[game.ticks()];
            if (!opt.record_path.empty()) record.push(actions);
            game.tick(actions);
        }
        const VkExtent2D extent = gpu.extent();
        const bool third = !opt.camera && opt.camera_mode == CameraMode::Third;
        const FpsCamera view = opt.camera ? *opt.camera : third ? game.third_person() : game.camera();
        renderer.set_view_proj(FpsCamera::proj(float(extent.width) / float(extent.height)) * view.view());
        renderer.set_character(game.feet(), game.facing(), game.locomotion(), third);
        renderer.set_props(game.props());

        const bool capturing = opt.capture_frame >= 0;
        const float t = fixed_step ? static_cast<float>(paused ? opt.pause_at : frames) / 60.0f : game.ticks() * Game::kDt;
        if (frames == opt.capture_frame) renderer.capture_next(opt.capture_path);
        if (!opt.capture_dir.empty()) {
            char name[32];
            std::snprintf(name, sizeof(name), "/frame_%05ld.png", frames);
            renderer.capture_next(opt.capture_dir + name);
        }
#ifdef GAME_HOT
        if (watch) watch->poll();
#endif
        renderer.draw_frame({{0.05f, 0.06f, 0.08f, 1.0f}}, t);
        FrameMark;
        stats.cpu_ms.push_back((SDL_GetTicksNS() - frame_start - renderer.blocked_ns()) * 1e-6);
        if (auto ms = renderer.gpu_ms()) stats.gpu_ms.push_back(*ms);
        if (auto ms = renderer.post_ms()) stats.post_ms.push_back(*ms);
        for (size_t p = 0; p < kGpuPasses; p++)
            if (auto ms = renderer.pass_ms(static_cast<GpuPass>(p))) stats.pass_ms[p].push_back(*ms);
        const VramUsage vram = gpu.vram();
        vram_peak.used = std::max(vram_peak.used, vram.used);
        vram_peak.budget = std::max(vram_peak.budget, vram.budget);
        frames++;
        window_frames++;

        const Uint64 now = SDL_GetTicksNS();
        if (now - window_start >= SDL_NS_PER_SECOND) {
            std::printf("FPS t=%.1f fps=%.1f\n", (now - start) * 1e-9, window_frames * 1e9 / (now - window_start));
            window_start = now;
            window_frames = 0;
        }
        if (capturing && frames > opt.capture_frame) running = false;
    }
    const double seconds = (SDL_GetTicksNS() - start) * 1e-9;
    const FpsCamera& cam = game.camera();
    std::printf("GAME pose x=%.6f y=%.6f z=%.6f yaw=%.6f pitch=%.6f ticks=%ld pickups=%d win_tick=%ld\n",
                cam.position.x, cam.position.y, cam.position.z, cam.yaw, cam.pitch, game.ticks(), game.collected(),
                game.win_tick());
    if (!opt.camera && opt.camera_mode == CameraMode::Third) {
        const FpsCamera arm = game.third_person();
        std::printf("CAMERA third x=%.6f y=%.6f z=%.6f\n", arm.position.x, arm.position.y, arm.position.z);
    }
    if (!opt.record_path.empty()) record.save(opt.record_path);
    const ValidationCounts& v = gpu.validation();
    const std::string vram_used = vram_peak.used < 0 ? "n/a" : std::to_string(vram_peak.used >> 20);
    const DrawStats& draws = renderer.draw_stats();
    std::string pass_fields;
    for (size_t p = 0; p < kGpuPasses; p++) {
        char field[64];
        std::snprintf(field, sizeof(field), "%s=%.4f ", gpu_pass_key(static_cast<GpuPass>(p)),
                      FrameStats::percentile(stats.pass_ms[p], 0.5));
        pass_fields += field;
    }
    std::printf("DONE frames=%ld seconds=%.3f avg_fps=%.1f validation_errors=%u validation_warnings=%u "
                "gpu_ms_p50=%.4f gpu_ms_p99=%.4f cpu_ms_p50=%.4f post_ms_p50=%.4f %svram_used_mb=%s vram_budget_mb=%llu draws=%u culled=%u "
                "lods=%u/%u/%u pos=%.9g,%.9g,%.9g\n",
                frames, seconds, frames / seconds, v.errors, v.warnings, FrameStats::percentile(stats.gpu_ms, 0.5),
                FrameStats::percentile(stats.gpu_ms, 0.99), FrameStats::percentile(stats.cpu_ms, 0.5),
                FrameStats::percentile(stats.post_ms, 0.5), pass_fields.c_str(),
                vram_used.c_str(), static_cast<unsigned long long>(vram_peak.budget >> 20), draws.draws, draws.culled,
                draws.lods[0], draws.lods[1], draws.lods[2], cam.position.x, cam.position.y, cam.position.z);
    std::fflush(stdout);
    return v.errors == 0 ? 0 : 2;
}

}  // namespace

int main(int argc, char** argv) {
    install_crash_handler();
    const Options opt = parse_args(argc, argv);
    if (opt.crash_test) crash_test();
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD)) {
        std::fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window* window = SDL_CreateWindow("cpp-vulkan-game", opt.width, opt.height, SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE);
    if (!window) {
        std::fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    int rc = 1;
    try {
        rc = run(opt, window);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "fatal: %s\n", e.what());
    }
    SDL_DestroyWindow(window);
    SDL_Quit();
    return rc;
}
