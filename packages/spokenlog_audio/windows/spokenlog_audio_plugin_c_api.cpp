#include "include/spokenlog_audio/spokenlog_audio_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "spokenlog_audio_plugin.h"

void SpokenlogAudioPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  spokenlog_audio::SpokenlogAudioPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
