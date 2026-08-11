// Copyright 2026 SunPad project
// SPDX-License-Identifier: GPL-2.0-or-later

// Hosts the ModernGekko / Dolphin-derived compatibility runtime inside the
// SunPad Android app: owns the game thread, the ANativeWindow render surface
// handed to the Vulkan video backend, and the pipe-input bridge. This is the
// C++ mirror of the iOS SunPadCoreHost.

#pragma once

#include <android/native_window.h>

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

#include "input_pipe.hpp"

namespace moderngekko {
class Runtime;
}

namespace sunpad {

enum class AspectRatioMode { Original = 0, Widescreen = 1, FillScreen = 2 };

class RuntimeHost {
 public:
  RuntimeHost() = default;
  ~RuntimeHost();
  RuntimeHost(const RuntimeHost&) = delete;
  RuntimeHost& operator=(const RuntimeHost&) = delete;

  // Boots the game on a background thread and returns immediately. The render
  // surface must have been provided beforehand through SetSurface. Returns an
  // empty string on success or a human-readable error message.
  std::string Start(const std::filesystem::path& game_root,
                    const std::filesystem::path& disc_image,
                    const std::filesystem::path& module_path,
                    const std::filesystem::path& user_directory);

  void Stop();
  void Pause();
  void Resume();

  // The Vulkan backend renders into this ANativeWindow; pass nullptr when the
  // surface is destroyed (the runtime is paused around that).
  void SetSurface(ANativeWindow* surface);

  // Publishes a normalized input snapshot to the Pipes device (~60 Hz).
  void PublishInput(const InputState& input);

  void SetRenderScale(int scale);
  void SetAspectRatioMode(AspectRatioMode mode);
  void SetModernCStick(bool enabled);

  double CurrentFPS() const;
  double CurrentSpeed() const;
  std::string EfbResolution() const;
  bool IsRunning() const { return running_.load(); }

 private:
  void RunGame(const std::filesystem::path& game_root,
               const std::filesystem::path& disc_image,
               const std::filesystem::path& module_path,
               const std::filesystem::path& user_directory);
  void ApplyAspectRatioMode(AspectRatioMode mode);
  void ApplyPendingSettings();
  void OpenPipe(const std::filesystem::path& user_directory);

  std::thread game_thread_;
  std::mutex runtime_mutex_;
  moderngekko::Runtime* runtime_ = nullptr;
  std::atomic<bool> stop_requested_{false};
  std::atomic<bool> starting_{false};
  std::atomic<bool> running_{false};
  int pipe_fd_ = -1;
  uint16_t last_buttons_ = 0;
  bool modern_cstick_ = false;
  int pending_scale_ = 1;
  AspectRatioMode pending_aspect_ = AspectRatioMode::Original;
  ANativeWindow* current_surface_ = nullptr;
  std::function<void(const std::string&)> on_error_;
};

}  // namespace sunpad
