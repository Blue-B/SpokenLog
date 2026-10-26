#include "spokenlog_audio_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace spokenlog_audio {

namespace {

using Microsoft::WRL::ComPtr;

constexpr UINT kConvertDoneMessage = WM_APP + 0x5A1;

struct ConvertJob {
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  std::string error;
};

std::wstring Utf8ToWide(const std::string &text) {
  if (text.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                                 static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      wide.data(), size);
  return wide;
}

void PutU32(std::vector<char> &out, uint32_t v) {
  for (int i = 0; i < 4; i++) out.push_back(static_cast<char>((v >> (8 * i)) & 0xff));
}

void PutU16(std::vector<char> &out, uint16_t v) {
  out.push_back(static_cast<char>(v & 0xff));
  out.push_back(static_cast<char>((v >> 8) & 0xff));
}

std::vector<char> WavHeader(uint32_t data_bytes) {
  std::vector<char> h;
  for (char c : std::string("RIFF")) h.push_back(c);
  PutU32(h, 36 + data_bytes);
  for (char c : std::string("WAVEfmt ")) h.push_back(c);
  PutU32(h, 16);
  PutU16(h, 1);  // PCM
  PutU16(h, 1);  // mono
  PutU32(h, 16000);
  PutU32(h, 32000);  // byte rate
  PutU16(h, 2);      // block align
  PutU16(h, 16);     // bits per sample
  for (char c : std::string("data")) h.push_back(c);
  PutU32(h, data_bytes);
  return h;
}

// Streaming linear resampler: output sample k sits at source position
// k * source_rate / 16000. Mirrors the Android implementation.
// shortcut: no low-pass before downsampling, fine for speech; add a filter if
// music imports sound harsh.
class MonoResampler {
 public:
  uint32_t source_rate = 16000;
  std::vector<char> pending;

  void Push(float sample) {
    source_index_ += 1;
    if (source_index_ == 0) previous_ = sample;
    const double step = source_rate / 16000.0;
    while (out_index_ * step <= source_index_) {
      const float frac =
          static_cast<float>(1.0 - (source_index_ - out_index_ * step));
      const float v = std::clamp(previous_ + (sample - previous_) * frac, -1.0f, 1.0f);
      PutU16(pending, static_cast<uint16_t>(static_cast<int16_t>(v * 32767)));
      out_index_ += 1;
    }
    previous_ = sample;
  }

 private:
  // Doubles avoid int64-to-double conversion warnings; exact up to 2^53.
  double source_index_ = -1;
  double out_index_ = 0;
  float previous_ = 0;
};

// Decodes the first audio stream of `source` to 16 kHz mono PCM16 WAV, the
// format local engines read. Returns an error message, empty on success.
std::string DecodeToWav(const std::wstring &source, const std::wstring &target) {
  const HRESULT co = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(MFStartup(MF_VERSION))) {
    if (SUCCEEDED(co)) CoUninitialize();
    return "Media Foundation is unavailable";
  }
  std::string error;
  {
    ComPtr<IMFSourceReader> reader;
    ComPtr<IMFMediaType> pcm;
    ComPtr<IMFMediaType> actual;
    UINT32 channels = 0;
    UINT32 rate = 0;
    if (FAILED(MFCreateSourceReaderFromURL(source.c_str(), nullptr, &reader)) ||
        FAILED(reader->SetStreamSelection(
            static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE)) ||
        FAILED(reader->SetStreamSelection(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), TRUE)) ||
        FAILED(MFCreateMediaType(&pcm)) ||
        FAILED(pcm->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio)) ||
        FAILED(pcm->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM)) ||
        FAILED(pcm->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16)) ||
        FAILED(reader->SetCurrentMediaType(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), nullptr,
            pcm.Get())) ||
        FAILED(reader->GetCurrentMediaType(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), &actual)) ||
        FAILED(actual->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels)) ||
        FAILED(actual->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &rate)) ||
        channels == 0 || rate == 0) {
      error = "Unsupported or unreadable audio file";
    } else {
      std::ofstream out(target.c_str(), std::ios::binary | std::ios::trunc);
      std::vector<char> blank(44, 0);
      out.write(blank.data(), static_cast<std::streamsize>(blank.size()));
      MonoResampler resampler;
      resampler.source_rate = rate;
      uint64_t data_bytes = 0;
      while (out) {
        DWORD flags = 0;
        ComPtr<IMFSample> sample;
        if (FAILED(reader->ReadSample(
                static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), 0,
                nullptr, &flags, nullptr, &sample))) {
          error = "Could not decode audio";
          break;
        }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
        if (!sample) continue;
        ComPtr<IMFMediaBuffer> buffer;
        BYTE *data = nullptr;
        DWORD length = 0;
        if (FAILED(sample->ConvertToContiguousBuffer(&buffer)) ||
            FAILED(buffer->Lock(&data, nullptr, &length))) {
          error = "Could not read decoded audio";
          break;
        }
        const auto *pcm16 = reinterpret_cast<const int16_t *>(data);
        const size_t frames = length / (2 * channels);
        for (size_t f = 0; f < frames; f++) {
          float sum = 0;
          for (UINT32 c = 0; c < channels; c++) sum += pcm16[f * channels + c] / 32768.0f;
          resampler.Push(sum / static_cast<float>(channels));
        }
        buffer->Unlock();
        out.write(resampler.pending.data(),
                  static_cast<std::streamsize>(resampler.pending.size()));
        data_bytes += resampler.pending.size();
        resampler.pending.clear();
      }
      if (error.empty() && data_bytes == 0) error = "No audio decoded";
      if (error.empty()) {
        const auto header = WavHeader(static_cast<uint32_t>(data_bytes));
        out.seekp(0);
        out.write(header.data(), static_cast<std::streamsize>(header.size()));
      }
      out.close();
      if (error.empty() && out.fail()) error = "Could not write WAV file";
    }
  }
  MFShutdown();
  if (SUCCEEDED(co)) CoUninitialize();
  if (!error.empty()) DeleteFileW(target.c_str());
  return error;
}

const std::string *StringArg(const flutter::EncodableMap &args, const char *key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

}  // namespace

// static
void SpokenlogAudioPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "spokenlog_audio",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SpokenlogAudioPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

SpokenlogAudioPlugin::SpokenlogAudioPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  // Conversion runs on a worker thread; results must be sent from the
  // platform thread, so the worker posts a message back to the window.
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [](HWND, UINT message, WPARAM, LPARAM lparam) -> std::optional<LRESULT> {
        if (message != kConvertDoneMessage) return std::nullopt;
        std::unique_ptr<ConvertJob> job(reinterpret_cast<ConvertJob *>(lparam));
        if (job->error.empty()) {
          job->result->Success();
        } else {
          job->result->Error("convert_failed", job->error);
        }
        return 0;
      });
}

SpokenlogAudioPlugin::~SpokenlogAudioPlugin() {
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
}

void SpokenlogAudioPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() != "convertToWav") {
    result->NotImplemented();
    return;
  }
  const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  const std::string *source = args ? StringArg(*args, "source") : nullptr;
  const std::string *target = args ? StringArg(*args, "target") : nullptr;
  if (!source || !target) {
    result->Error("bad_args", "source and target required");
    return;
  }
  HWND window = GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
  auto *job = new ConvertJob{std::move(result), ""};
  std::thread([window, job, wide_source = Utf8ToWide(*source),
               wide_target = Utf8ToWide(*target)]() {
    job->error = DecodeToWav(wide_source, wide_target);
    PostMessage(window, kConvertDoneMessage, 0, reinterpret_cast<LPARAM>(job));
  }).detach();
}

}  // namespace spokenlog_audio
