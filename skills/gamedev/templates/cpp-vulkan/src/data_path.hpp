#pragma once

#include <SDL3/SDL_filesystem.h>

#include <string>

/** Path of a file or directory relative to the executable's directory. */
inline std::string game_data_path(const char* name) { return std::string(SDL_GetBasePath()) + name; }
