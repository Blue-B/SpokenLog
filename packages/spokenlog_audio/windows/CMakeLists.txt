cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "spokenlog_audio")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "spokenlog_audio_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/spokenlog_audio/spokenlog_audio_plugin_c_api.h"
  "spokenlog_audio_plugin_c_api.cpp"
  "spokenlog_audio_plugin.cpp"
  "spokenlog_audio_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
# Media Foundation decodes M4A/MP3/WMA/MP4 and more without extra DLLs.
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  mfplat mfreadwrite mfuuid)

set(spokenlog_audio_bundled_libraries
  ""
  PARENT_SCOPE
)
