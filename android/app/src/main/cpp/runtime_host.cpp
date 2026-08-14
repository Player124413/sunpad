// Copyright 2026 SunPad project
// SPDX-License-Identifier: GPL-2.0-or-later

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "runtime_host.hpp"

#include <errno.h>
#include <fcntl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef ANDROID
#include <dirent.h>
#include <sched.h>
#endif

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <exception>
#include <fstream>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

#include "Common/Config/Config.h"
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
extern "C" void SunPadSetLogQuiet(bool quiet);

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
  // iOS forbids W^X. Official Dolphin Android uses JitArm64 — without it
  // SMS's 138 SMC ranges hit the interpreter and Honor X9b crawls at
  // ~half the FPS of the same game in Dolphin.
#ifndef ANDROID
  ::setenv("STATICRECOMP_NO_FALLBACK_JIT", "1", 1);
#endif
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
#ifdef ANDROID
  SunPadNativeLog("early init: panic logged, ARM64 JIT fallback on, analytics stub set");
#else
  SunPadNativeLog("early init: panic logged, fallback JIT disabled, analytics stub set");
#endif
}

}  // namespace sunpad

namespace {

struct AndroidDeviceProfile {
  int cores = 1;
  long mem_mb = 0;
  long max_mhz = 0;
  int mt_model = 0;
  bool mediatek = false;
  bool mali = false;
  bool adreno = false;
  bool weak = false;
  bool gpu_weak = false;
  char tag[48] = "generic";
};

std::string ReadProp(const char* key) {
#ifdef ANDROID
  char val[PROP_VALUE_MAX] = {};
  __system_property_get(key, val);
  return val;
#else
  (void)key;
  return {};
#endif
}

std::string ReadFileHead(const char* path) {
  FILE* f = std::fopen(path, "r");
  if (!f)
    return {};
  char buf[192];
  const size_t n = std::fread(buf, 1, sizeof(buf) - 1, f);
  std::fclose(f);
  buf[n] = '\0';
  return buf;
}

void AppendLower(std::string& dst, const std::string& src) {
  dst.push_back(' ');
  for (unsigned char c : src)
    dst.push_back(static_cast<char>(std::tolower(c)));
}

int ParseMtModel(const std::string& blob) {
  for (size_t i = 0; i + 6 <= blob.size(); ++i) {
    if (blob[i] == 'm' && blob[i + 1] == 't' && std::isdigit(blob[i + 2]) &&
        std::isdigit(blob[i + 3]) && std::isdigit(blob[i + 4]) &&
        std::isdigit(blob[i + 5])) {
      return (blob[i + 2] - '0') * 1000 + (blob[i + 3] - '0') * 100 +
             (blob[i + 4] - '0') * 10 + (blob[i + 5] - '0');
    }
  }
  return 0;
}

bool Contains(const std::string& blob, const char* needle) {
  return blob.find(needle) != std::string::npos;
}

// Cheap phones (Helio G, Unisoc, old Snapdragon 4xx/6xx, 3–4 GB RAM)
// get a 90% guest clock so they stay playable. Midrange like SD 6 Gen 1
// (Adreno 710, ~2.2 GHz, 6+ GB) stays at full GameCube speed.
// MediaTek is special: CPU clocks look fine, Mali is the bottleneck, and
// Vulkan on Mali often black-screens. Helio / low Dimensity count as weak.
AndroidDeviceProfile DetectAndroidDevice() {
  AndroidDeviceProfile p;
  const long n = ::sysconf(_SC_NPROCESSORS_CONF);
  p.cores = n > 0 ? static_cast<int>(n) : 1;

  if (FILE* f = std::fopen("/proc/meminfo", "r")) {
    char line[160];
    while (std::fgets(line, sizeof(line), f)) {
      long kb = 0;
      if (std::sscanf(line, "MemTotal: %ld kB", &kb) == 1 ||
          std::sscanf(line, "MemTotal: %ld", &kb) == 1) {
        p.mem_mb = kb / 1024;
        break;
      }
    }
    std::fclose(f);
  }

  for (int i = 0; i < p.cores && i < 8; ++i) {
    char path[96];
    std::snprintf(path, sizeof(path),
                  "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_max_freq", i);
    if (FILE* f = std::fopen(path, "r")) {
      long khz = 0;
      if (std::fscanf(f, "%ld", &khz) == 1 && khz / 1000 > p.max_mhz)
        p.max_mhz = khz / 1000;
      std::fclose(f);
    }
  }

  std::string blob;
  AppendLower(blob, ReadProp("ro.hardware"));
  AppendLower(blob, ReadProp("ro.board.platform"));
  AppendLower(blob, ReadProp("ro.hardware.egl"));
  AppendLower(blob, ReadProp("ro.soc.manufacturer"));
  AppendLower(blob, ReadProp("ro.soc.model"));
  AppendLower(blob, ReadProp("ro.product.board"));
  AppendLower(blob, ReadFileHead("/proc/cpuinfo"));
  AppendLower(blob, ReadFileHead("/sys/class/misc/mali0/device/gpuinfo"));
  AppendLower(blob, ReadFileHead("/sys/class/misc/mali0/device/modalias"));

  p.mediatek = Contains(blob, "mediatek") || Contains(blob, "dimensity") ||
               Contains(blob, "helio") || ParseMtModel(blob) > 0;
  p.mali = Contains(blob, "mali") || Contains(blob, "immortalis") ||
           ::access("/sys/class/misc/mali0", F_OK) == 0 ||
           ::access("/sys/module/mali_kbase", F_OK) == 0 ||
           ::access("/dev/mali0", F_OK) == 0;
  p.adreno = Contains(blob, "adreno") || Contains(blob, "kgsl") ||
             ::access("/dev/kgsl-3d0", F_OK) == 0 ||
             ::access("/sys/class/kgsl", F_OK) == 0;
  p.mt_model = ParseMtModel(blob);

  const bool helio =
      p.mt_model >= 6700 && p.mt_model < 6785;  // below Helio G90T
  const bool low_dimensity = p.mt_model == 6833 || p.mt_model == 6835 ||
                             p.mt_model == 6853 || p.mt_model == 6855;
  const bool weak_mali_name =
      Contains(blob, "mali-g31") || Contains(blob, "mali-g51") ||
      Contains(blob, "mali-g52") || Contains(blob, "mali-g57") ||
      Contains(blob, "mali-g68");

  p.weak = (p.mem_mb > 0 && p.mem_mb < 3500) || p.cores <= 4 ||
           (p.max_mhz > 0 && p.max_mhz < 2050) || helio || low_dimensity ||
           weak_mali_name;
  // Any Mali / MediaTek below Dimensity 1200 class is fill-rate limited
  // at a 2400px panel even when the CPU looks midrange on paper.
  p.gpu_weak = p.weak || p.mali ||
               (p.mediatek && (p.mt_model == 0 || p.mt_model < 6893));

  if (p.mediatek && p.mt_model > 0)
    std::snprintf(p.tag, sizeof(p.tag), "mtk-mt%d%s", p.mt_model,
                  p.mali ? "-mali" : "");
  else if (p.adreno)
    std::snprintf(p.tag, sizeof(p.tag), "adreno");
  else if (p.mali)
    std::snprintf(p.tag, sizeof(p.tag), "mali");
  else if (p.mediatek)
    std::snprintf(p.tag, sizeof(p.tag), "mediatek");
  else
    std::snprintf(p.tag, sizeof(p.tag), "generic");
  return p;
}

const AndroidDeviceProfile& CachedDevice() {
  static const AndroidDeviceProfile p = DetectAndroidDevice();
  return p;
}

#ifdef ANDROID
cpu_set_t g_big_cpus;
bool g_big_ready = false;
int g_big_count = 0;

void DiscoverBigCores() {
  CPU_ZERO(&g_big_cpus);
  long khz[16] = {};
  int n = 0;
  long max_khz = 0;
  for (int i = 0; i < 16; ++i) {
    char path[96];
    std::snprintf(path, sizeof(path),
                  "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_max_freq", i);
    FILE* f = std::fopen(path, "r");
    if (!f)
      break;
    if (std::fscanf(f, "%ld", &khz[i]) == 1) {
      if (khz[i] > max_khz)
        max_khz = khz[i];
      n = i + 1;
    }
    std::fclose(f);
  }
  int pinned = 0;
  for (int i = 0; i < n; ++i) {
    if (max_khz <= 0 || khz[i] * 100 >= max_khz * 85) {
      CPU_SET(i, &g_big_cpus);
      ++pinned;
    }
  }
  if (pinned == 0) {
    const int fallback = n > 0 ? n : 8;
    for (int i = 0; i < fallback; ++i)
      CPU_SET(i, &g_big_cpus);
    pinned = fallback;
  }
  g_big_count = pinned;
  g_big_ready = true;
}

void PinCurrentToBigCores() {
  if (!g_big_ready)
    DiscoverBigCores();
  if (::sched_setaffinity(0, sizeof(cpu_set_t), &g_big_cpus) == 0) {
    char buf[72];
    std::snprintf(buf, sizeof(buf), "pinned host thread to %d big cores",
                  g_big_count);
    SunPadNativeLog(buf);
  }
}

bool NameLooksLikeEmu(const char* name) {
  return std::strstr(name, "CPU") != nullptr ||
         std::strstr(name, "GPU") != nullptr ||
         std::strstr(name, "DSP") != nullptr ||
         std::strstr(name, "Emu") != nullptr ||
         std::strstr(name, "Audio") != nullptr ||
         std::strstr(name, "OpenSL") != nullptr ||
         std::strstr(name, "Video") != nullptr;
}

void BoostNamedEmuThreads() {
  if (!g_big_ready)
    DiscoverBigCores();
  DIR* d = ::opendir("/proc/self/task");
  if (!d)
    return;
  int boosted = 0;
  while (dirent* e = ::readdir(d)) {
    if (e->d_name[0] == '.')
      continue;
    char comm_path[64];
    std::snprintf(comm_path, sizeof(comm_path), "/proc/self/task/%s/comm",
                  e->d_name);
    FILE* f = std::fopen(comm_path, "r");
    if (!f)
      continue;
    char name[32] = {};
    if (std::fgets(name, sizeof(name), f) == nullptr) {
      std::fclose(f);
      continue;
    }
    std::fclose(f);
    if (!NameLooksLikeEmu(name))
      continue;
    const int tid = std::atoi(e->d_name);
    if (tid <= 0)
      continue;
    ::sched_setaffinity(tid, sizeof(cpu_set_t), &g_big_cpus);
    ::setpriority(PRIO_PROCESS, tid, -16);
    ++boosted;
  }
  ::closedir(d);
  static int last_boosted = -1;
  if (boosted > 0 && boosted != last_boosted) {
    last_boosted = boosted;
    char buf[72];
    std::snprintf(buf, sizeof(buf), "boosted %d emu threads onto big cores",
                  boosted);
    SunPadNativeLog(buf);
  }
}
#endif

void BoostHostThreads() {
  // Best-effort: Android may reject a negative nice. Failure is ignored.
  ::setpriority(PRIO_PROCESS, 0, -16);
#ifdef ANDROID
  PinCurrentToBigCores();
#endif
}

void FitPresentBuffer(ANativeWindow* surface) {
  if (surface == nullptr)
    return;
  // Official Dolphin presents at the SurfaceView size. The old 0.5× / 1280
  // ANativeWindow resize made Adreno hitch and looked worse than Dolphin.
  ANativeWindow_setBuffersGeometry(surface, 0, 0, WINDOW_FORMAT_RGBA_8888);
}

template <typename T>
void SetCfg(const Config::Info<T>& info, const T& value) {
  Config::SetBase(info, value);
  Config::SetCurrent(info, value);
}

void PrepareAndroidUserTree(const fs::path& user_directory) {
  sunpad::EarlyInit();

  std::error_code ec;
  fs::create_directories(user_directory / "Sys", ec);
  fs::create_directories(user_directory / "Dump", ec);
  fs::create_directories(user_directory / "Cache", ec);
  fs::create_directories(user_directory / "GC", ec);
  fs::create_directories(user_directory / "Load", ec);
  fs::create_directories(user_directory / "Shaders", ec);

  // Never wipe Cache/: official Dolphin stays smooth because specialized
  // pipelines persist. A wipe forces every plaza/menu shader to compile
  // again and looks like a freeze.
  const fs::path cache_dir = user_directory / "Cache";
  fs::create_directories(cache_dir, ec);

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
    BoostHostThreads();
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
      config.enable_gmse01_60fps = false;
      config.module =
          moderngekko::ModuleSource::DynamicPath(module_path.string());
      config.render_surface = current_surface_;
      std::fprintf(stderr, "[sunpad] creating runtime backend=%s surface=%p %dx%d\n",
                   backend, static_cast<void*>(current_surface_),
                   current_surface_ ? ANativeWindow_getWidth(current_surface_) : 0,
                   current_surface_ ? ANativeWindow_getHeight(current_surface_) : 0);
      SunPadNativeLog("creating runtime (30 FPS)");
      return moderngekko::Runtime::Create(std::move(config));
    };

    const auto& dev = CachedDevice();
    // Mali / MediaTek Vulkan is a common black screen. Always try GLES first
    // on those chips; Snapdragon can still honour the user's Vulkan toggle.
    const bool force_gles = dev.mali || dev.mediatek;
    const char* first =
        (force_gles || preferred_backend_ == "OGL") ? "OGL" : "Vulkan";
    const char* second = first[0] == 'O' ? "Vulkan" : "OGL";
    std::fprintf(stderr, "[sunpad] preferred backend=%s force_gles=%d soc=%s\n",
                 first, force_gles ? 1 : 0, dev.tag);
    if (force_gles)
      SunPadNativeLog("MediaTek/Mali: forcing OpenGL ES");
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

#ifdef ANDROID
    std::thread([this] {
      for (int i = 0; i < 10 && !stop_requested_.load(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(350));
        BoostNamedEmuThreads();
      }
    }).detach();
#endif

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
    FitPresentBuffer(surface);
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
  // POWERPC / HOST_GPU / MEMMAP spam a file write every guest burst and
  // murder weak 64-bit SoCs. Keep boot + fatal video/core only.
  const LT types[] = {LT::BOOT, LT::VIDEO, LT::CORE, LT::CONSOLE};
  for (const LT type : types)
    mgr->SetEnable(type, true);
  mgr->SetConfigLogLevel(Common::Log::LogLevel::LWARNING);

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
  SunPadNativeLog("dolphin logs: BOOT/VIDEO/CORE (quiet after boot)");
}

void RuntimeHost::ApplyPendingSettings() {
  const auto& dev = CachedDevice();
  const int scale = pending_scale_ < 1 ? 1 : pending_scale_;
  SetCfg(Config::GFX_EFB_SCALE, scale);
  SetCfg(Config::GFX_MAX_EFB_SCALE, 12);
  // Use specialized shaders on every GPU. Uber shaders fail to link on some
  // Adreno devices and are not reliable enough for this app's fixed profile.
  SetCfg(Config::GFX_SHADER_COMPILATION_MODE,
         ShaderCompilationMode::Synchronous);
  SetCfg(Config::GFX_WAIT_FOR_SHADERS_BEFORE_STARTING, true);
  const int shader_threads = (!dev.weak && !dev.mali && dev.cores > 4) ? 2 : 1;
  SetCfg(Config::GFX_SHADER_PRECOMPILER_THREADS, shader_threads);
  SetCfg(Config::GFX_SHADER_COMPILER_THREADS, shader_threads);
  SetCfg(Config::GFX_BACKEND_MULTITHREADING, false);
  SetCfg(Config::GFX_PREFER_GLES, true);
  SetCfg(Config::GFX_SHADER_CACHE, true);
  // Official Dolphin Android uses the JIT vertex loader. Software is why
  // Honor X9b (Adreno 710) is half-speed here vs a stable 30 FPS there.
  SetCfg(Config::GFX_VERTEX_LOADER_TYPE, VertexLoaderType::Native);
  SetCfg(Config::MAIN_FASTMEM, true);
  // Dual-core stays enabled for every device; the app deliberately does not
  // offer a single-core mode because Sunshine needs the CPU and GPU threads.
  SetCfg(Config::MAIN_CPU_THREAD, true);
  // Official Dolphin default. Dual-core + skip-idle unsynced is a common
  // hitch on SMS; matching Dolphin Android here.
  SetCfg(Config::MAIN_SYNC_ON_SKIP_IDLE, true);
  SetCfg(Config::MAIN_FAST_DISC_SPEED, true);
  SetCfg(Config::MAIN_SKIP_IPL, true);
  SetCfg(Config::MAIN_DSP_HLE, true);
  SetCfg(Config::MAIN_DSP_THREAD, dev.cores > 4);
  SetCfg(Config::MAIN_SYNC_GPU, false);
  SetCfg(Config::MAIN_MMU, false);
  SetCfg(Config::MAIN_ACCURATE_CPU_CACHE, false);
  // Honor X9b has 8–12 GB. Loading the 1.4 GB ISO stops level/menu
  // hitches from flash I/O — official Dolphin's "load to RAM".
  const bool ram_load = dev.mem_mb >= 5500;
  SetCfg(Config::MAIN_LOAD_GAME_INTO_MEMORY, ram_load);
  // Official Dolphin locked 30: wait for VI, do not present early.
  // Rush + Immediate XFB on a 120 Hz panel looks like stutter even at 30.
  SetCfg(Config::MAIN_PRECISION_FRAME_TIMING, true);
  SetCfg(Config::MAIN_RUSH_FRAME_PRESENTATION, false);
  SetCfg(Config::MAIN_AUDIO_FILL_GAPS, true);
  SetCfg(Config::MAIN_AUDIO_BUFFER_SIZE, (dev.weak || dev.gpu_weak) ? 160 : 120);
  SetCfg(Config::GFX_VSYNC, false);
  SetCfg(Config::GFX_MSAA, 1u);
  SetCfg(Config::GFX_SSAA, false);
  SetCfg(Config::GFX_ENABLE_PIXEL_LIGHTING, false);
  SetCfg(Config::GFX_CPU_CULL, false);
  SetCfg(Config::GFX_HIRES_TEXTURES, false);
  SetCfg(Config::GFX_CACHE_HIRES_TEXTURES, false);
  SetCfg(Config::GFX_DUMP_TEXTURES, false);
  SetCfg(Config::GFX_ENABLE_WIREFRAME, false);
  SetCfg(Config::GFX_DISABLE_FOG, false);
  SetCfg(Config::GFX_ENHANCE_FORCE_TEXTURE_FILTERING,
         TextureFilteringMode::Default);
  SetCfg(Config::GFX_ENHANCE_MAX_ANISOTROPY, AnisotropicFilteringMode::Force1x);
  SetCfg(Config::GFX_ENHANCE_DISABLE_COPY_FILTER, true);
  SetCfg(Config::GFX_HACK_FAST_TEXTURE_SAMPLING, true);
  SetCfg(Config::GFX_HACK_EFB_DEFER_INVALIDATION, true);
  SetCfg(Config::GFX_HACK_EARLY_XFB_OUTPUT, true);
  SetCfg(Config::GFX_HACK_VERTEX_ROUNDING, false);
  // Official Dolphin default is off. VI skip drops frames on purpose —
  // that is the "просадка" vs a locked 30 FPS in Dolphin Android.
  SetCfg(Config::GFX_HACK_VI_SKIP, false);
  SetCfg(Config::GFX_SAFE_TEXTURE_CACHE_COLOR_SAMPLES, 128);

  // Super Mario Sunshine (Data/Sys/GameSettings/GMS.ini): CPU must read
  // the EFB and copies must land in RAM, or goop / water / FLUDD break.
  // GPU texture decode fights arbitrary-mip graffiti. Fast depth flickers
  // on GLES. Scaled EFB copies smear the goo. Immediate XFB is off in
  // official Dolphin — it desyncs presents from VI and looks like hitch.
  SetCfg(Config::GFX_HACK_EFB_ACCESS_ENABLE, true);
  SetCfg(Config::GFX_HACK_SKIP_EFB_COPY_TO_RAM, false);
  SetCfg(Config::GFX_HACK_DEFER_EFB_COPIES, true);
  SetCfg(Config::GFX_HACK_MISSING_COLOR_VALUE, 0u);
  SetCfg(Config::GFX_PERF_QUERIES_ENABLE, true);
  SetCfg(Config::GFX_ENHANCE_ARBITRARY_MIPMAP_DETECTION, true);
  SetCfg(Config::GFX_ENABLE_GPU_TEXTURE_DECODING, false);
  SetCfg(Config::GFX_HACK_COPY_EFB_SCALED, false);
  // Fast depth flickers on Mali GLES. Adreno (Honor X9b) matches official
  // Dolphin with it on — a free chunk of GPU time.
  SetCfg(Config::GFX_FAST_DEPTH_CALC, !dev.mali);
  SetCfg(Config::GFX_HACK_IMMEDIATE_XFB, false);
  SetCfg(Config::GFX_HACK_SKIP_DUPLICATE_XFBS, true);

  // Weak 64-bit SoCs cannot hold 100% guest speed. 90% GC clock keeps
  // Delfino playable without dropping frames.
  if (dev.weak) {
    SetCfg(Config::MAIN_OVERCLOCK_ENABLE, true);
    SetCfg(Config::MAIN_OVERCLOCK, 0.90f);
  } else {
    SetCfg(Config::MAIN_OVERCLOCK_ENABLE, false);
    SetCfg(Config::MAIN_OVERCLOCK, 1.0f);
  }

  char buf[256];
  std::snprintf(buf, sizeof(buf),
                "graphics: dual-core=1 GLES 30fps ram-iso=%d vi-skip=0 "
                "specialized=1 soc=%s cores=%d ram=%ldMB weak=%d",
                ram_load ? 1 : 0, dev.tag, dev.cores, dev.mem_mb,
                dev.weak ? 1 : 0);
  SunPadNativeLog(buf);

  // After boot, stop appending every Dolphin line to the crash log.
  std::thread([] {
    std::this_thread::sleep_for(std::chrono::seconds(8));
    SunPadSetLogQuiet(true);
  }).detach();

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
