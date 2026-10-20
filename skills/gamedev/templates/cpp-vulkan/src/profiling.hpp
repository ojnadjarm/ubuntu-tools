// Tracy zone macros when built with GAME_TRACY=ON, no-ops otherwise.
#pragma once

#ifdef TRACY_ENABLE
#include <tracy/Tracy.hpp>
#else
#define ZoneScoped
#define ZoneScopedN(name)
#define FrameMark
#endif
