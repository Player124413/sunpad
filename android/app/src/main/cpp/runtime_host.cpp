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
#include <memory>
#include <mutex>
#include <optional>

#include "Core/Config/GraphicsSettings.h"
#include "Core/Config/MainSettings.h"
#include "Core/Core.h"
#include "Core/DolphinAnalytics.h"
#include "Core/System.h"
#include "Common/Logging/Log.h"
#include "Common/Logging/LogManager.h"
#include "Common/MsgHandler.h"
#include "VideoCommon/PerformanceMetrics.h"
#include "VideoCommon/VideoConfig.h"
#include "moderngekko/runtime.hpp"

#include <cstdlib>
#include <string>

// FileUtil.h pulls jni/AndroidCommon/AndroidCommon.h under ANDROID; that
// header is not on this target's include path. Declare the one API we need.
#ifdef ANDROID
namespace File {
void SetSysDirectory(const std::string& path);
const std::string& GetSysDirectory();
}
#endif

// Implemented by the SunPad Dolphin patch in PlatformAndroid.cpp.
extern "C" void ModernGekkoSetAndroidRenderSurface(void* surface);
extern "C" void SunPadNativeLog(const char* msg);

namespace fs = std::filesystem;

namespace {

bool SunPadAlert(const char* caption, const char* text, bool /*yes_no*/,
                 Common::MsgType /*style*/) {
  char buf[1536];
  std::snprintf(buf, sizeof(buf), "DOLPHIN ALERT [%s]: %s",
                caption ? caption : "?", text ? text : "");
  SunPadNativeLog(buf);
  // true = "Ignore and continue" so ASSERT_MSG does not call Crash().
  return true;
}

}  // namespace

namespace sunpad {

void EarlyInit() {
  static bool done = false;
  if (done)
    return;
  done = true;
  Common::SetAbortOnPanicAlert(false);
  Common::RegisterMsgAlertHandler(&SunPadAlert);
  ::setenv("STATICRECOMP_NO_FALLBACK_JIT", "1", 1);
#ifdef ANDROID
  DolphinAnalytics::AndroidSetGetValFunc([](std::string key) -> std::string {
    if (key == "DEVICE_MANUFACTURER")
      return "SunPad";
    if (key == "DEVICE_MODEL")
      return "Android";
    if (key == "DEVICE_OS")
      return "8+";
    return {};
  });
#endif
  std::set_terminate([] {
    SunPadNativeLog("std::terminate: uncaught C++ exception");
    try {
      throw;
    } catch (const std::exception& ex) {
      char buf[512];
      std::snprintf(buf, sizeof(buf), "exception: %s", ex.what());
      SunPadNativeLog(buf);
    } catch (...) {
      SunPadNativeLog("exception: unknown");
    }
  });
  SunPadNativeLog("early init: panic logged, fallback JIT disabled, analytics stub set");
}

}  // namespace sunpad

namespace {

void PrepareAndroidUserTree(const fs::path& user_directory) {
  sunpad::EarlyInit();

  std::error_code ec;
  fs::create_directories(user_directory / "Sys", ec);
  fs::create_directories(user_directory / "Dump", ec);
  fs::create_directories(user_directory / "Cache", ec);
  fs::create_directories(user_directory / "GC", ec);
  fs::create_directories(user_directory / "Load", ec);
  fs::create_directories(user_directory / "Shaders", ec);

  // Stale uber-shader cache from earlier APKs crashes the Adreno compiler
  // on load. Wipe once when upgrading to specialized-on-demand.
  const fs::path cache_dir = user_directory / "Cache";
  const fs::path cache_marker = cache_dir / ".sunpad_shader_v2";
  if (!fs::exists(cache_marker)) {
    fs::remove_all(cache_dir, ec);
    fs::create_directories(cache_dir, ec);
    std::ofstream(cache_marker.string()) << "specialized-v2\n";
    SunPadNativeLog("wiped stale shader cache");
  }

  // Android FileUtil ASSERT-aborts the process if this is never set
  // ("Sys directory has not been set") — that is SIGABRT after shaders.
  static bool sys_set = false;
  if (!sys_set) {
#ifdef ANDROID
    File::SetSysDirectory((user_directory / "Sys").string());
    SunPadNativeLog(
        ("GetSysDirectory() => " + File::GetSysDirectory()).c_str());
#endif
    sys_set = true;
    SunPadNativeLog(
        ("Sys directory set to " + (user_directory / "Sys").string()).c_str());
  }
}

}  // namespace

namespace sunpad {

RuntimeHost::~RuntimeHost() {
  Stop();
}

std::string RuntimeHost::Start(const fs::path& game_root,
                               const fs::path& disc_image,
                               const fs::path& module_path,
                               const fs::path& user_directory) {
  // A previous Run() that already finished still leaves game_thread_ joinable
  // until Stop(). Join it so a retry is not "runtime already running".
  if (game_thread_.joinable() && !running_.load() && !starting_.load())
    game_thread_.join();
  if (running_.load() || starting_.load() || game_thread_.joinable())
    return "runtime already running";
  if (current_surface_ == nullptr)
    return "The screen is not ready yet. Close any dialogs and try again.";
  if (module_path.empty() || !fs::exists(module_path))
    return "Game module is missing (gGMSE01_recomp.so).";
  if (game_root.empty() || !fs::exists(game_root))
    return "Extracted game data is missing.";

  last_run_error_.clear();
  stop_requested_.store(false);
  starting_.store(true);

  {
    std::error_code iso_ec;
    const auto iso_size =
        disc_image.empty() ? 0 : fs::file_size(disc_image, iso_ec);
    std::error_code mod_ec;
    const auto mod_size = fs::file_size(module_path, mod_ec);
    char boot_info[384];
    std::snprintf(boot_info, sizeof(boot_info),
                  "boot files: iso=%s (%llu bytes) module=%s (%llu bytes) "
                  "surface=%dx%d",
                  disc_image.string().c_str(),
                  static_cast<unsigned long long>(iso_ec ? 0 : iso_size),
                  module_path.string().c_str(),
                  static_cast<unsigned long long>(mod_ec ? 0 : mod_size),
                  current_surface_ ? ANativeWindow_getWidth(current_surface_) : 0,
                  current_surface_ ? ANativeWindow_getHeight(current_surface_) : 0);
    SunPadNativeLog(boot_info);
  }

  PrepareAndroidUserTree(user_directory);

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

  // running_ is set just before Run(). Stay ~2s after that: if EmuThread
  // dies immediately we return the real reason instead of a generic dialog.
  for (int i = 0; i < 50 && !stop_requested_.load(); ++i) {
    if (running_.load()) {
      for (int j = 0; j < 20 && running_.load() && !stop_requested_.load(); ++j)
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
      if (!running_.load() && !stop_requested_.load()) {
        if (game_thread_.joinable())
          game_thread_.join();
        return last_run_error_.empty()
                   ? "The game stopped while booting. Use ••• → Copy diagnostic log."
                   : last_run_error_;
      }
      return "";
    }
    if (!starting_.load() && !running_.load() && i > 0) {
      if (game_thread_.joinable())
        game_thread_.join();
      return last_run_error_.empty()
                 ? "The game stopped while booting. Use ••• → Copy diagnostic log."
                 : last_run_error_;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
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
      std::fprintf(stderr, "[sunpad] creating runtime backend=%s surface=%p %dx%d\n",
                   backend, static_cast<void*>(current_surface_),
                   current_surface_ ? ANativeWindow_getWidth(current_surface_) : 0,
                   current_surface_ ? ANativeWindow_getHeight(current_surface_) : 0);
      SunPadNativeLog("creating runtime");
      return moderngekko::Runtime::Create(std::move(config));
    };

    const char* first =
        preferred_backend_ == "OGL" ? "OGL" : "Vulkan";
    const char* second = preferred_backend_ == "OGL" ? "Vulkan" : "OGL";
    std::fprintf(stderr, "[sunpad] preferred backend=%s\n", first);
    auto created = try_create(first);
    if (!created) {
      const std::string first_error = created.error ? created.error->message
                                                    : "unknown error";
      std::fprintf(stderr, "[sunpad] %s create failed: %s; trying %s\n",
                   first, first_error.c_str(), second);
      created = try_create(second);
      if (!created) {
        const std::string second_error = created.error ? created.error->message
                                                       : "unknown error";
        error_message = std::string(first) + " failed (" + first_error +
                        "); " + second + " also failed (" + second_error + ")";
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
    EnableDolphinLogs();
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

    // Open the pipe in parallel: the runtime only creates the reader inside
    // Run(), so waiting here first used to stall boot for up to 60s and then
    // leave input disconnected.
    SunPadNativeLog("runtime created; entering Run() (shaders / first present next)");
    std::fprintf(stderr, "[sunpad] entering Run()\n");
    std::thread pipe_thread([this, user_directory] { OpenPipe(user_directory); });
    auto result = created.runtime->Run();
    if (pipe_thread.joinable())
      pipe_thread.join();
    const std::string run_msg = result.error
        ? ("Run() returned error: " + result.error->message)
        : "Run() returned (emulation stopped)";
    last_run_error_ = result.error ? result.error->message : run_msg;
    SunPadNativeLog(run_msg.c_str());
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
    last_run_error_ = ex.what();
    starting_.store(false);
    running_.store(false);
    notify_created(ex.what());
    return;
  } catch (...) {
    last_run_error_ = "The game runtime aborted while starting.";
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
  if (surface != nullptr) {
    current_surface_ = surface;
    ANativeWindow_setBuffersGeometry(surface, 0, 0, WINDOW_FORMAT_RGBA_8888);
  }
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

void RuntimeHost::SetPreferredBackend(std::string backend) {
  if (backend == "OGL" || backend == "Vulkan")
    preferred_backend_ = std::move(backend);
}

void RuntimeHost::EnableDolphinLogs() {
  auto* mgr = Common::Log::LogManager::GetInstance();
  if (mgr == nullptr) {
    SunPadNativeLog("dolphin LogManager not ready");
    return;
  }
  using LT = Common::Log::LogType;
  const LT types[] = {LT::BOOT,     LT::VIDEO,    LT::CORE,    LT::POWERPC,
                      LT::COMMON,   LT::AUDIO,    LT::CONSOLE, LT::HOST_GPU,
                      LT::OSHLE,    LT::MEMMAP,   LT::VIDEOINTERFACE};
  for (const LT type : types)
    mgr->SetEnable(type, true);
  mgr->SetConfigLogLevel(Common::Log::LogLevel::LNOTICE);

  class SunPadLogListener final : public Common::Log::LogListener {
   public:
    void Log(Common::Log::LogLevel, const char* msg) override {
      SunPadNativeLog(msg);
    }
  };
  mgr->RegisterListener(Common::Log::LogListener::LOG_WINDOW_LISTENER,
                        std::make_unique<SunPadLogListener>());
  mgr->EnableListener(Common::Log::LogListener::LOG_WINDOW_LISTENER, true);
  mgr->EnableListener(Common::Log::LogListener::CONSOLE_LISTENER, true);
  SunPadNativeLog("dolphin logs: BOOT/VIDEO/CORE/POWERPC → diagnostic log");
}

void RuntimeHost::ApplyPendingSettings() {
  Config::SetCurrent(Config::GFX_EFB_SCALE, pending_scale_);
  Config::SetCurrent(Config::GFX_MAX_EFB_SCALE, 12);
  // Adreno cannot link Dolphin ubershaders. Keep specialized + one
  // compiler thread. Dual-core (CPU vs GPU threads) is safe and is what
  // official Dolphin Android uses — single-core was a crash workaround
  // that left the game at a crawl.
  Config::SetBase(Config::GFX_SHADER_COMPILATION_MODE,
                  ShaderCompilationMode::Synchronous);
  Config::SetCurrent(Config::GFX_SHADER_COMPILATION_MODE,
                     ShaderCompilationMode::Synchronous);
  Config::SetBase(Config::GFX_WAIT_FOR_SHADERS_BEFORE_STARTING, false);
  Config::SetCurrent(Config::GFX_WAIT_FOR_SHADERS_BEFORE_STARTING, false);
  Config::SetBase(Config::GFX_SHADER_PRECOMPILER_THREADS, 1);
  Config::SetCurrent(Config::GFX_SHADER_PRECOMPILER_THREADS, 1);
  Config::SetBase(Config::GFX_SHADER_COMPILER_THREADS, 1);
  Config::SetCurrent(Config::GFX_SHADER_COMPILER_THREADS, 1);
  Config::SetBase(Config::GFX_BACKEND_MULTITHREADING, false);
  Config::SetCurrent(Config::GFX_BACKEND_MULTITHREADING, false);
  Config::SetBase(Config::GFX_PREFER_GLES, true);
  Config::SetCurrent(Config::GFX_PREFER_GLES, true);
  Config::SetBase(Config::MAIN_CPU_THREAD, true);
  Config::SetCurrent(Config::MAIN_CPU_THREAD, true);
  Config::SetBase(Config::MAIN_SYNC_ON_SKIP_IDLE, false);
  Config::SetCurrent(Config::MAIN_SYNC_ON_SKIP_IDLE, false);
  Config::SetBase(Config::MAIN_FAST_DISC_SPEED, true);
  Config::SetCurrent(Config::MAIN_FAST_DISC_SPEED, true);

  // Super Mario Sunshine (Data/Sys/GameSettings/GMS.ini): CPU must read
  // the EFB and copies must land in RAM, or goop / water / FLUDD break.
  // GPU texture decode fights arbitrary-mip graffiti. Fast depth flickers
  // on GLES. Scaled EFB copies smear the goo. Immediate XFB + skip
  // duplicate frames cut latency without changing the image.
  Config::SetBase(Config::GFX_HACK_EFB_ACCESS_ENABLE, true);
  Config::SetCurrent(Config::GFX_HACK_EFB_ACCESS_ENABLE, true);
  Config::SetBase(Config::GFX_HACK_SKIP_EFB_COPY_TO_RAM, false);
  Config::SetCurrent(Config::GFX_HACK_SKIP_EFB_COPY_TO_RAM, false);
  Config::SetBase(Config::GFX_HACK_DEFER_EFB_COPIES, true);
  Config::SetCurrent(Config::GFX_HACK_DEFER_EFB_COPIES, true);
  Config::SetBase(Config::GFX_HACK_MISSING_COLOR_VALUE, 0u);
  Config::SetCurrent(Config::GFX_HACK_MISSING_COLOR_VALUE, 0u);
  Config::SetBase(Config::GFX_PERF_QUERIES_ENABLE, true);
  Config::SetCurrent(Config::GFX_PERF_QUERIES_ENABLE, true);
  Config::SetBase(Config::GFX_ENHANCE_ARBITRARY_MIPMAP_DETECTION, true);
  Config::SetCurrent(Config::GFX_ENHANCE_ARBITRARY_MIPMAP_DETECTION, true);
  Config::SetBase(Config::GFX_ENABLE_GPU_TEXTURE_DECODING, false);
  Config::SetCurrent(Config::GFX_ENABLE_GPU_TEXTURE_DECODING, false);
  Config::SetBase(Config::GFX_HACK_COPY_EFB_SCALED, false);
  Config::SetCurrent(Config::GFX_HACK_COPY_EFB_SCALED, false);
  Config::SetBase(Config::GFX_FAST_DEPTH_CALC, false);
  Config::SetCurrent(Config::GFX_FAST_DEPTH_CALC, false);
  Config::SetBase(Config::GFX_HACK_IMMEDIATE_XFB, true);
  Config::SetCurrent(Config::GFX_HACK_IMMEDIATE_XFB, true);
  Config::SetBase(Config::GFX_HACK_SKIP_DUPLICATE_XFBS, true);
  Config::SetCurrent(Config::GFX_HACK_SKIP_DUPLICATE_XFBS, true);
  SunPadNativeLog(
      "graphics: dual-core, specialized GLES, SMS EFB-to-RAM, no fast-depth");
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
