// Copyright 2026 SunPad project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "runtime_host.hpp"

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <exception>
#include <fstream>
#include <mutex>
#include <optional>

#include "Core/Config/GraphicsSettings.h"
#include "Core/Config/MainSettings.h"
#include "Core/Core.h"
#include "Core/System.h"
#include "VideoCommon/PerformanceMetrics.h"
#include "VideoCommon/VideoConfig.h"
#include "moderngekko/runtime.hpp"

// Implemented by the SunPad Dolphin patch in PlatformAndroid.cpp.
extern "C" void ModernGekkoSetAndroidRenderSurface(void* surface);

namespace fs = std::filesystem;

namespace sunpad {

RuntimeHost::~RuntimeHost() {
  Stop();
}

std::string RuntimeHost::Start(const fs::path& game_root,
                               const fs::path& disc_image,
                               const fs::path& module_path,
                               const fs::path& user_directory) {
  if (running_.load() || starting_.load() || game_thread_.joinable())
    return "runtime already running";
  if (current_surface_ == nullptr)
    return "The screen is not ready yet. Close any dialogs and try again.";
  if (module_path.empty() || !fs::exists(module_path))
    return "Game module is missing (gGMSE01_recomp.so).";
  if (game_root.empty() || !fs::exists(game_root))
    return "Extracted game data is missing.";

  stop_requested_.store(false);
  starting_.store(true);

  // The runtime opens the FIFO read-only; recreate if a stale file exists.
  const fs::path pipe_dir = user_directory / "Pipes";
  std::error_code ec;
  fs::create_directories(pipe_dir, ec);
  const fs::path pipe_path = pipe_dir / "sunpad";
  ::unlink(pipe_path.c_str());
  if (::mkfifo(pipe_path.c_str(), 0666) != 0)
    std::fprintf(stderr, "[sunpad] mkfifo failed errno=%d\n", errno);

  // Provide the pipe device mapping before the runtime initializes
  // controllers (mirrors the iOS app's provisioning step).
  const fs::path config_dir = user_directory / "Config";
  fs::create_directories(config_dir, ec);
  {
    std::ofstream ini(config_dir / "GCPadNew.ini", std::ios::trunc);
    ini << GCPadNewIniContents();
  }

  std::mutex created_mutex;
  std::condition_variable created_cv;
  std::string create_error;
  bool create_done = false;

  game_thread_ = std::thread([this, game_root, disc_image, module_path,
                              user_directory, &created_mutex, &created_cv,
                              &create_error, &create_done] {
    RunGame(game_root, disc_image, module_path, user_directory,
            [&](const std::string& error) {
              {
                std::lock_guard lock(created_mutex);
                create_error = error;
                create_done = true;
              }
              created_cv.notify_one();
            });
  });

  {
    std::unique_lock lock(created_mutex);
    created_cv.wait(lock, [&] { return create_done; });
  }

  if (!create_error.empty()) {
    if (game_thread_.joinable())
      game_thread_.join();
    starting_.store(false);
    running_.store(false);
    return create_error;
  }
  return "";
}

void RuntimeHost::RunGame(const fs::path& game_root,
                          const fs::path& disc_image,
                          const fs::path& module_path,
                          const fs::path& user_directory,
                          const std::function<void(const std::string&)>& on_created) {
  std::string error_message;
  bool notified = false;
  const auto notify_created = [&](const std::string& error) {
    if (notified)
      return;
    notified = true;
    if (on_created)
      on_created(error);
  };
  try {
    if (current_surface_ == nullptr) {
      error_message = "The screen was lost before the game could start.";
      starting_.store(false);
      std::fprintf(stderr, "[sunpad] %s\n", error_message.c_str());
      notify_created(error_message);
      return;
    }

    const auto try_create = [&](const char* backend) {
      moderngekko::RuntimeConfig config;
      config.game_root = game_root.string();
      if (!disc_image.empty())
        config.disc_image = disc_image.string();
      config.user_directory = user_directory.string();
      config.graphics.backend = backend;
      config.headless = false;
      config.show_fps_in_title = false;
      config.module =
          moderngekko::ModuleSource::DynamicPath(module_path.string());
      config.render_surface = current_surface_;
      std::fprintf(stderr, "[sunpad] creating runtime backend=%s surface=%p\n",
                   backend, static_cast<void*>(current_surface_));
      return moderngekko::Runtime::Create(std::move(config));
    };

    auto created = try_create("Vulkan");
    if (!created) {
      const std::string vulkan_error = created.error ? created.error->message
                                                     : "unknown Vulkan error";
      std::fprintf(stderr, "[sunpad] Vulkan create failed: %s; trying OGL\n",
                   vulkan_error.c_str());
      created = try_create("OGL");
      if (!created) {
        const std::string ogl_error = created.error ? created.error->message
                                                    : "unknown OpenGL ES error";
        error_message = "Vulkan failed (" + vulkan_error +
                        "); OpenGL ES also failed (" + ogl_error + ")";
      }
    }
    if (!created) {
      if (error_message.empty()) {
        error_message = created.error ? created.error->message
                                      : "Could not create the game runtime.";
      }
      starting_.store(false);
      std::fprintf(stderr, "[sunpad] runtime create failed: %s\n",
                   error_message.c_str());
      notify_created(error_message);
      if (on_error_)
        on_error_(error_message);
      return;
    }
    notify_created("");
    {
      std::scoped_lock lock(runtime_mutex_);
      runtime_ = created.runtime.get();
    }
    if (stop_requested_.load()) {
      std::scoped_lock lock(runtime_mutex_);
      runtime_ = nullptr;
      starting_.store(false);
      return;
    }
    starting_.store(false);
    running_.store(true);
    std::fprintf(stderr, "[sunpad] runtime created\n");

    ApplyPendingSettings();

    // Open the input FIFO for writing (blocks until the runtime reads it).
    OpenPipe(user_directory);

    auto result = created.runtime->Run();
    {
      std::scoped_lock lock(runtime_mutex_);
      runtime_ = nullptr;
    }
    std::fprintf(stderr, "[sunpad] runtime exited error=%d stopRequested=%d\n",
                 static_cast<bool>(result.error), stop_requested_.load());
    if (result.error && on_error_)
      on_error_(result.error->message);
    if (pipe_fd_ >= 0) {
      ::close(pipe_fd_);
      pipe_fd_ = -1;
    }
  } catch (const std::exception& ex) {
    starting_.store(false);
    running_.store(false);
    notify_created(ex.what());
    return;
  } catch (...) {
    starting_.store(false);
    running_.store(false);
    notify_created("The game runtime aborted while starting.");
    return;
  }
  running_.store(false);
  starting_.store(false);
}

void RuntimeHost::OpenPipe(const fs::path& user_directory) {
  const fs::path pipe_path = user_directory / "Pipes" / "sunpad";
  for (int attempt = 0; attempt < 600 && !stop_requested_.load(); ++attempt) {
    pipe_fd_ = ::open(pipe_path.c_str(), O_WRONLY | O_NONBLOCK);
    if (pipe_fd_ >= 0) {
      std::fprintf(stderr, "[sunpad] input pipe connected attempt=%d\n",
                   attempt + 1);
      return;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  std::fprintf(stderr, "[sunpad] input pipe unavailable after wait errno=%d\n",
               errno);
}

void RuntimeHost::Stop() {
  stop_requested_.store(true);
  {
    std::scoped_lock lock(runtime_mutex_);
    if (runtime_ != nullptr)
      runtime_->RequestStop();
  }
  if (game_thread_.joinable())
    game_thread_.join();
  starting_.store(false);
  running_.store(false);
}

void RuntimeHost::Pause() {
  std::scoped_lock lock(runtime_mutex_);
  if (runtime_ != nullptr)
    runtime_->Pause();
}

void RuntimeHost::Resume() {
  std::scoped_lock lock(runtime_mutex_);
  if (runtime_ != nullptr)
    runtime_->Resume();
}

void RuntimeHost::SetSurface(ANativeWindow* surface) {
  // Never forget the last live window: surfaceDestroyed used to pass
  // nullptr here, and the next Start then handed a null ANativeWindow to
  // Vulkan — which aborts the process and looks like "the game crashed
  // after import".
  if (surface != nullptr)
    current_surface_ = surface;
  ModernGekkoSetAndroidRenderSurface(surface != nullptr ? surface
                                                        : current_surface_);
}

void RuntimeHost::PublishInput(const InputState& input) {
  if (pipe_fd_ < 0)
    return;
  const std::string commands =
      EncodePipeCommands(input, last_buttons_, modern_cstick_);
  if (commands.empty())
    return;
  const ssize_t written = ::write(pipe_fd_, commands.data(), commands.size());
  if (written == static_cast<ssize_t>(commands.size())) {
    // Advance edge tracking only after the whole atomic FIFO message is
    // delivered; an EAGAIN retries the same button transition next frame.
    last_buttons_ = input.buttons;
  } else if (written < 0 && errno != EAGAIN) {
    std::fprintf(stderr, "[sunpad] pipe write failed errno=%d\n", errno);
  }
}

void RuntimeHost::SetRenderScale(int scale) {
  const int clamped = scale < 1 ? 1 : (scale > 4 ? 4 : scale);
  pending_scale_ = clamped;
  if (!running_.load())
    return;
  // Config::SetCurrent is mutex-protected; the video backend refreshes
  // g_ActiveConfig on the next config callback.
  Config::SetCurrent(Config::GFX_EFB_SCALE, clamped);
}

void RuntimeHost::SetAspectRatioMode(AspectRatioMode mode) {
  pending_aspect_ = mode;
  if (!running_.load())
    return;
  ApplyAspectRatioMode(mode);
}

void RuntimeHost::SetModernCStick(bool enabled) {
  modern_cstick_ = enabled;
}

void RuntimeHost::ApplyPendingSettings() {
  Config::SetCurrent(Config::GFX_EFB_SCALE, pending_scale_);
  Config::SetCurrent(Config::GFX_MAX_EFB_SCALE, 12);
  ApplyAspectRatioMode(pending_aspect_);
}

void RuntimeHost::ApplyAspectRatioMode(AspectRatioMode mode) {
  switch (mode) {
    case AspectRatioMode::Widescreen:
      Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::ForceWide);
      Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, true);
      break;
    case AspectRatioMode::FillScreen:
      if (current_surface_ != nullptr &&
          ANativeWindow_getWidth(current_surface_) > 0 &&
          ANativeWindow_getHeight(current_surface_) > 0) {
        Config::SetCurrent(Config::GFX_CUSTOM_ASPECT_RATIO_WIDTH,
                           ANativeWindow_getWidth(current_surface_));
        Config::SetCurrent(Config::GFX_CUSTOM_ASPECT_RATIO_HEIGHT,
                           ANativeWindow_getHeight(current_surface_));
      }
      Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::CustomStretch);
      Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, true);
      break;
    case AspectRatioMode::Original:
    default:
      Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::ForceStandard);
      Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, false);
      break;
  }
}

double RuntimeHost::CurrentFPS() const {
  if (!running_.load())
    return 0.0;
  return Core::System::GetInstance().GetPerfMetrics().GetFPS();
}

double RuntimeHost::CurrentSpeed() const {
  if (!running_.load())
    return 0.0;
  return Core::System::GetInstance().GetPerfMetrics().GetSpeed();
}

std::string RuntimeHost::EfbResolution() const {
  if (!running_.load())
    return "";
  const auto& metrics = Core::System::GetInstance().GetPerfMetrics();
  char buffer[32];
  std::snprintf(buffer, sizeof(buffer), "%ux%u", metrics.GetEFBWidth(),
                metrics.GetEFBHeight());
  return buffer;
}

}  // namespace sunpad
