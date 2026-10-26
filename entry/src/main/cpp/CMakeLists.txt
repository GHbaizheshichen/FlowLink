cmake_minimum_required(VERSION 3.16.0)
project(HarmonyProxy)
enable_language(C ASM)

if(DEFINED PACKAGE_FIND_FILE)
  include(${PACKAGE_FIND_FILE})
endif()

add_library(proxy_core SHARED napi_init.cpp proxy_core/proxy_core.cpp)
# hev-socks5-tunnel 2.9.0 (99cd2d5d) + submodules, vendored into the repo.
set(HEV "${CMAKE_CURRENT_SOURCE_DIR}/third-party/hev-socks5-tunnel")
file(GLOB_RECURSE HEV_SOURCES "${HEV}/src/*.c" "${HEV}/src/*.S"
  "${HEV}/third-part/lwip/src/*.c" "${HEV}/third-part/lwip/src/*.S"
  "${HEV}/third-part/hev-task-system/src/*.c" "${HEV}/third-part/hev-task-system/src/*.S"
  "${HEV}/third-part/yaml/src/*.c")
list(FILTER HEV_SOURCES EXCLUDE REGEX "/arch/")
add_library(hev STATIC ${HEV_SOURCES})
set_target_properties(hev PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(hev PUBLIC "${HEV}/src" "${HEV}/src/misc" "${HEV}/src/core/include"
  "${HEV}/third-part/lwip/src/include" "${HEV}/third-part/lwip/src/ports/include"
  "${HEV}/third-part/hev-task-system/include" "${HEV}/third-part/hev-task-system/src"
  "${HEV}/third-part/yaml/include")
target_compile_definitions(hev PRIVATE COMMIT_ID="99cd2d5" YAML_VERSION_MAJOR=0 YAML_VERSION_MINOR=2
  YAML_VERSION_PATCH=5 YAML_VERSION_STRING="0.2.5" ENABLE_STACK_OVERFLOW_DETECTION ENABLE_MEMALLOC_SLICE
  CONFIG_STACK_BACKEND=STACK_MMAP CONFIG_STACK_OVERFLOW_DETECTION=1 CONFIG_MEMALLOC_SLICE_ALIGN=64
  CONFIG_MEMALLOC_SLICE_MAX_SIZE=4096 CONFIG_MEMALLOC_SLICE_MAX_COUNT=1000 CONFIG_SCHED_CLOCK=CLOCK_NONE)
target_compile_options(hev PRIVATE -Wno-unused-command-line-argument)
target_link_options(proxy_core PRIVATE "-Wl,--wrap=hev_socks5_tunnel_run"
  "-Wl,--wrap=read" "-Wl,--wrap=readv" "-Wl,--wrap=write" "-Wl,--wrap=writev")
target_compile_features(proxy_core PRIVATE cxx_std_17)
# SDK 26 on Windows injects --gcc-toolchain, which its Clang no longer consumes.
target_compile_options(proxy_core PRIVATE -Wall -Wextra -Wno-unused-command-line-argument)
target_link_libraries(proxy_core PRIVATE hev libace_napi.z.so libnet_connection.so dl)
