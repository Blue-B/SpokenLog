#ifndef FLUTTER_PLUGIN_SPOKENLOG_AUDIO_PLUGIN_H_
#define FLUTTER_PLUGIN_SPOKENLOG_AUDIO_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace spokenlog_audio {

class SpokenlogAudioPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit SpokenlogAudioPlugin(flutter::PluginRegistrarWindows *registrar);

  virtual ~SpokenlogAudioPlugin();

  SpokenlogAudioPlugin(const SpokenlogAudioPlugin &) = delete;
  SpokenlogAudioPlugin &operator=(const SpokenlogAudioPlugin &) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  flutter::PluginRegistrarWindows *registrar_;
  int window_proc_id_ = -1;
};

}  // namespace spokenlog_audio

#endif  // FLUTTER_PLUGIN_SPOKENLOG_AUDIO_PLUGIN_H_
