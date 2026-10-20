cmake_minimum_required(VERSION 3.29)
project(cpp_vulkan_game LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(SDL3 CONFIG REQUIRED)
find_package(vk-bootstrap CONFIG REQUIRED)
find_package(volk CONFIG REQUIRED)
find_package(glm CONFIG REQUIRED)
find_package(Ktx CONFIG REQUIRED)
find_package(mikktspace CONFIG REQUIRED)
find_package(VulkanMemoryAllocator CONFIG REQUIRED)
find_package(Jolt CONFIG REQUIRED)
find_path(CGLTF_INCLUDE_DIR cgltf.h REQUIRED)
find_path(MINIAUDIO_INCLUDE_DIR miniaudio.h REQUIRED)
find_program(GLSLANG glslangValidator REQUIRED)
find_program(SPIRV_VAL spirv-val REQUIRED)

set(SHADER_DIR ${CMAKE_BINARY_DIR}/shaders)
foreach(shader mesh.vert mesh.frag shadow.vert skinned.vert post.vert post.frag bloom.comp ibl_prefilter.comp)
  set(spv ${SHADER_DIR}/${shader}.spv)
  add_custom_command(OUTPUT ${spv}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${SHADER_DIR}
    COMMAND ${GLSLANG} -V --target-env vulkan1.3 -o ${spv} ${CMAKE_SOURCE_DIR}/shaders/${shader}
    COMMAND ${SPIRV_VAL} --target-env vulkan1.3 ${spv}
    DEPENDS shaders/${shader}
    VERBATIM)
  list(APPEND SPIRV ${spv})
endforeach()
add_custom_target(shaders DEPENDS ${SPIRV})

add_executable(game src/main.cpp src/animation.cpp src/audio.cpp src/camera.cpp src/crash.cpp src/game.cpp src/gpu_context.cpp src/gpu_resources.cpp src/gpu_timer.cpp src/ibl.cpp src/input.cpp src/mesh.cpp
               src/physics.cpp src/pipeline.cpp src/post.cpp src/renderer.cpp src/miniaudio.cpp src/skinned_draw.cpp src/texture.cpp src/vma.cpp)
set_source_files_properties(src/vma.cpp src/miniaudio.cpp PROPERTIES COMPILE_OPTIONS -w)
add_dependencies(game shaders)
target_compile_options(game PRIVATE -Wall -Wextra -Wno-missing-designated-field-initializers $<$<CONFIG:Release>:-g1>)
target_compile_definitions(game PRIVATE GAME_NAME="${PROJECT_NAME}" VMA_STATIC_VULKAN_FUNCTIONS=0 VMA_DYNAMIC_VULKAN_FUNCTIONS=1)
target_include_directories(game SYSTEM PRIVATE ${CGLTF_INCLUDE_DIR} ${MINIAUDIO_INCLUDE_DIR})
target_link_libraries(game PRIVATE SDL3::SDL3 vk-bootstrap::vk-bootstrap volk::volk glm::glm-header-only KTX::ktx
                      mikktspace::mikktspace GPUOpen::VulkanMemoryAllocator Jolt::Jolt)

option(GAME_PORTABLE "Shaders, assets and the scene resolved next to the executable (cpp-ci package)" OFF)
target_compile_options(game PRIVATE -include ${CMAKE_SOURCE_DIR}/src/data_path.hpp)
if(GAME_PORTABLE)
  target_compile_definitions(game PRIVATE GAME_SHADER_DIR=game_data_path\("shaders"\) GAME_ASSET_DIR=game_data_path\("assets"\)
                             GAME_MODEL=game_data_path\("model_lod0.glb"\))
  set_target_properties(game PROPERTIES INSTALL_RPATH "$ORIGIN/lib")
  install(TARGETS game RUNTIME DESTINATION .)
  install(DIRECTORY ${SHADER_DIR} DESTINATION .)
  install(DIRECTORY assets DESTINATION . PATTERN "*.sh" EXCLUDE)
  file(GLOB SCENE_FILES ${CMAKE_SOURCE_DIR}/model_lod*.glb)
  install(FILES ${SCENE_FILES} DESTINATION .)
else()
  # paths relative to the executable keep compile commands identical across project copies (ccache hits)
  file(RELATIVE_PATH shader_rel ${CMAKE_BINARY_DIR} ${SHADER_DIR})
  file(RELATIVE_PATH asset_rel ${CMAKE_BINARY_DIR} ${CMAKE_SOURCE_DIR}/assets)
  target_compile_definitions(game PRIVATE GAME_SHADER_DIR=game_data_path\("${shader_rel}"\) GAME_ASSET_DIR=game_data_path\("${asset_rel}"\)
                             GAME_MODEL="model_lod0.glb")
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug" AND NOT GAME_PORTABLE)
  target_sources(game PRIVATE src/shader_watch.cpp)
  target_compile_definitions(game PRIVATE GAME_HOT)
  set_source_files_properties(src/shader_watch.cpp PROPERTIES COMPILE_DEFINITIONS
                              "GAME_SHADER_SRC_DIR=\"${CMAKE_SOURCE_DIR}/shaders\";GAME_GLSLANG=\"${GLSLANG}\";GAME_SPIRV_VAL=\"${SPIRV_VAL}\"")
endif()

option(GAME_TRACY "Tracy CPU zones (client listens on localhost only)" OFF)
if(GAME_TRACY)
  set(TRACY_ROOT "$ENV{HOME}/opt/gamedev/tracy-0.14.1" CACHE PATH "Tracy source tree (client version must match tracy-capture)")
  target_sources(game PRIVATE ${TRACY_ROOT}/public/TracyClient.cpp)
  set_source_files_properties(${TRACY_ROOT}/public/TracyClient.cpp PROPERTIES COMPILE_OPTIONS -w)
  target_include_directories(game SYSTEM PRIVATE ${TRACY_ROOT}/public)
  target_compile_definitions(game PRIVATE TRACY_ENABLE TRACY_ONLY_LOCALHOST)
endif()
