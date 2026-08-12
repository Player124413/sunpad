// Copyright 2026 SunPad project
// SPDX-License-Identifier: GPL-2.0-or-later

// JNI bridge for the SunPad Android app. Declarations live in
// com.sunpad.android.SunPadNative (Kotlin). The bridge owns the process
// JavaVM registration for the core's OpenSL ES backend and exposes the
// runtime host + DiscIO extraction to the app.

#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>

#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>

#include "Common/CommonTypes.h"
#include "DiscIO/DiscExtractor.h"
#include "DiscIO/Filesystem.h"
#include "DiscIO/Volume.h"

#include "input_pipe.hpp"
#include "runtime_host.hpp"

static JavaVM* g_vm = nullptr;
static sunpad::RuntimeHost* g_host = nullptr;
// Retained ANativeWindow reference: released only when replaced or at
// JNI_OnUnload. The runtime is paused around surface destruction, so the
// old window may stay referenced until a replacement arrives (Dolphin's
// Android app does the same).
static ANativeWindow* g_window = nullptr;

// Implemented by the SunPad Dolphin patch in IDCacheStub.cpp.
extern "C" void SunPadAndroidSetJavaVM(JavaVM* vm);

// AudioUtils is cached in JNI_OnLoad (app class loader). FindClass from an
// attached audio thread uses the system class loader and cannot see
// com.sunpad.android.AudioUtils — that left a pending JNI exception and
// aborted the process after ISO import.
static jclass g_audio_utils = nullptr;
static jmethodID g_audio_sample_rate = nullptr;
static jmethodID g_audio_frames = nullptr;

extern "C" bool SunPadAndroidQueryAudio(int* sample_rate, int* frames_per_buffer) {
  if (g_vm == nullptr || g_audio_utils == nullptr)
    return false;
  JNIEnv* env = nullptr;
  bool attached = false;
  if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
    attached = g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK;
    if (!attached)
      return false;
  }
  if (env == nullptr)
    return false;
  if (g_audio_sample_rate && sample_rate)
    *sample_rate = env->CallStaticIntMethod(g_audio_utils, g_audio_sample_rate);
  if (g_audio_frames && frames_per_buffer)
    *frames_per_buffer = env->CallStaticIntMethod(g_audio_utils, g_audio_frames);
  const bool ok = !env->ExceptionCheck();
  if (!ok)
    env->ExceptionClear();
  return ok;
}

namespace {

JNIEnv* AttachEnv() {
  JNIEnv* env = nullptr;
  if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK)
      return nullptr;
  }
  return env;
}

// ---------------------------------------------------------------------------
// GameInputState field access (cached after first use)

struct InputFieldIds {
  jclass cls = nullptr;
  jfieldID stickX = nullptr;
  jfieldID stickY = nullptr;
  jfieldID cStickX = nullptr;
  jfieldID cStickY = nullptr;
  jfieldID triggerL = nullptr;
  jfieldID triggerR = nullptr;
  jfieldID buttons = nullptr;
};

InputFieldIds& InputIds() {
  static InputFieldIds ids;
  static std::once_flag once;
  std::call_once(once, [] {
    JNIEnv* env = AttachEnv();
    ids.cls = static_cast<jclass>(env->NewGlobalRef(
        env->FindClass("com/sunpad/android/GameInputState")));
    ids.stickX = env->GetFieldID(ids.cls, "stickX", "I");
    ids.stickY = env->GetFieldID(ids.cls, "stickY", "I");
    ids.cStickX = env->GetFieldID(ids.cls, "cStickX", "I");
    ids.cStickY = env->GetFieldID(ids.cls, "cStickY", "I");
    ids.triggerL = env->GetFieldID(ids.cls, "triggerL", "I");
    ids.triggerR = env->GetFieldID(ids.cls, "triggerR", "I");
    ids.buttons = env->GetFieldID(ids.cls, "buttons", "I");
  });
  return ids;
}

// ---------------------------------------------------------------------------
// DiscIO extraction with progress listener

struct ExtractContext {
  std::string image_path;
  std::string destination;
  jobject listener;  // global ref
};

void RunExtraction(ExtractContext ctx) {
  JNIEnv* env = AttachEnv();
  if (env == nullptr) {
    // Cannot report progress without an environment; drop the listener ref
    // and give up. The Kotlin side shows the generic failure path.
    return;
  }
  const jclass listener_cls = env->GetObjectClass(ctx.listener);
  const jmethodID on_progress = env->GetMethodID(
      listener_cls, "onProgress", "(Ljava/lang/String;D)V");
  const jmethodID on_finished = env->GetMethodID(
      listener_cls, "onFinished", "(ZLjava/lang/String;)V");

  const auto report_progress = [&](const char* status, double fraction) {
    if (on_progress) {
      jstring js = env->NewStringUTF(status);
      env->CallVoidMethod(ctx.listener, on_progress, js, fraction);
      env->DeleteLocalRef(js);
    }
  };
  const auto finish = [&](bool ok, const char* message) {
    if (on_finished) {
      jstring js = message ? env->NewStringUTF(message) : nullptr;
      env->CallVoidMethod(ctx.listener, on_finished,
                          static_cast<jboolean>(ok), js);
      if (js) env->DeleteLocalRef(js);
    }
    env->DeleteLocalRef(listener_cls);
    env->DeleteGlobalRef(ctx.listener);
  };

  report_progress("Opening disc image", 0.0);
  std::unique_ptr<DiscIO::Volume> volume =
      DiscIO::CreateVolume(ctx.image_path);
  if (!volume) {
    finish(false, "Dolphin could not open the disc image.");
    return;
  }
  const DiscIO::Partition partition = volume->GetGamePartition();
  const DiscIO::FileSystem* filesystem = volume->GetFileSystem(partition);
  if (!filesystem || !filesystem->IsValid()) {
    finish(false, "Dolphin could not read the game filesystem.");
    return;
  }

  std::error_code ec;
  std::filesystem::path root = ctx.destination;
  std::filesystem::create_directories(root / "files", ec);
  if (ec) {
    finish(false, "Could not create the extraction directory.");
    return;
  }

  report_progress("Extracting system data", 0.05);
  if (!DiscIO::ExportSystemData(*volume, partition, root.string())) {
    finish(false, "System-data extraction failed.");
    return;
  }

  const u64 total = std::max<u64>(1, filesystem->GetRoot().GetTotalChildren());
  std::atomic<u64> completed{0};
  report_progress("Extracting game files", 0.10);
  DiscIO::ExportDirectory(
      *volume, partition, filesystem->GetRoot(), true, "",
      (root / "files").string(),
      [&completed, total, &report_progress](const std::string& path) {
        ++completed;
        const double fraction = 0.10 + 0.85 * static_cast<double>(completed.load()) /
                                            static_cast<double>(total);
        report_progress(path.c_str(), fraction);
        return false;  // continue
      });

  finish(true, nullptr);
}

}  // namespace

// ---------------------------------------------------------------------------
// JNI_OnLoad / JNI_OnUnload

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
  g_vm = vm;
  SunPadAndroidSetJavaVM(vm);
  g_host = new sunpad::RuntimeHost();
  return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT void JNI_OnUnload(JavaVM* vm, void* reserved) {
  delete g_host;
  g_host = nullptr;
  if (g_window != nullptr) {
    ANativeWindow_release(g_window);
    g_window = nullptr;
  }
  g_vm = nullptr;
}

// ---------------------------------------------------------------------------
// Runtime lifecycle

extern "C" JNIEXPORT jstring JNICALL
Java_com_sunpad_android_SunPadNative_nativeStart(
    JNIEnv* env, jobject, jstring game_root, jstring disc_image,
    jstring module_path, jstring user_directory) {
  if (!g_host)
    return env->NewStringUTF("Native runtime is not initialized.");
  const auto to_path = [env](jstring js) {
    if (!js) return std::filesystem::path();
    const char* chars = env->GetStringUTFChars(js, nullptr);
    std::filesystem::path path(chars ? chars : "");
    if (chars) env->ReleaseStringUTFChars(js, chars);
    return path;
  };
  const std::string error = g_host->Start(
      to_path(game_root), to_path(disc_image), to_path(module_path),
      to_path(user_directory));
  if (error.empty())
    return nullptr;
  return env->NewStringUTF(error.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativeStop(JNIEnv*, jobject) {
  if (g_host) g_host->Stop();
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativePause(JNIEnv*, jobject) {
  if (g_host) g_host->Pause();
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativeResume(JNIEnv*, jobject) {
  if (g_host) g_host->Resume();
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativeSetSurface(JNIEnv* env, jobject,
                                                      jobject surface) {
  if (!g_host) return;
  ANativeWindow* window = nullptr;
  if (surface != nullptr) {
    window = ANativeWindow_fromSurface(env, surface);
    if (g_window != nullptr)
      ANativeWindow_release(g_window);
    g_window = window;
    g_host->SetSurface(window);
    return;
  }
  // A null surface only pauses emulation (the Activity does that); the old
  // window reference is kept until a replacement arrives so Start() never
  // sees a nullptr ANativeWindow (that aborted Vulkan after ISO import).
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativePublishInput(JNIEnv* env, jobject,
                                                        jobject state) {
  if (!g_host) return;
  const InputFieldIds& ids = InputIds();
  sunpad::InputState input;
  input.stickX = static_cast<int8_t>(env->GetIntField(state, ids.stickX));
  input.stickY = static_cast<int8_t>(env->GetIntField(state, ids.stickY));
  input.cStickX = static_cast<int8_t>(env->GetIntField(state, ids.cStickX));
  input.cStickY = static_cast<int8_t>(env->GetIntField(state, ids.cStickY));
  input.triggerL = static_cast<uint8_t>(env->GetIntField(state, ids.triggerL));
  input.triggerR = static_cast<uint8_t>(env->GetIntField(state, ids.triggerR));
  input.buttons = static_cast<uint16_t>(env->GetIntField(state, ids.buttons));
  g_host->PublishInput(input);
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativeSetRenderScale(JNIEnv*, jobject,
                                                          jint scale) {
  if (g_host) g_host->SetRenderScale(scale);
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativeSetAspectRatioMode(JNIEnv*, jobject,
                                                              jint mode) {
  if (g_host) g_host->SetAspectRatioMode(
      static_cast<sunpad::AspectRatioMode>(mode));
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativeSetModernCStick(JNIEnv*, jobject,
                                                           jboolean enabled) {
  if (g_host) g_host->SetModernCStick(enabled == JNI_TRUE);
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_sunpad_android_SunPadNative_nativeCurrentFPS(JNIEnv*, jobject) {
  return g_host ? g_host->CurrentFPS() : 0.0;
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_sunpad_android_SunPadNative_nativeCurrentSpeed(JNIEnv*, jobject) {
  return g_host ? g_host->CurrentSpeed() : 0.0;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_sunpad_android_SunPadNative_nativeEfbResolution(JNIEnv* env,
                                                         jobject) {
  const std::string resolution = g_host ? g_host->EfbResolution() : "";
  return env->NewStringUTF(resolution.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_sunpad_android_SunPadNative_nativeIsRunning(JNIEnv*, jobject) {
  return g_host && g_host->IsRunning() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_sunpad_android_SunPadNative_nativeExtractImage(
    JNIEnv* env, jobject, jstring image_path, jstring destination,
    jobject listener) {
  if (!listener || !g_vm)
    return;
  ExtractContext ctx;
  const char* ip = env->GetStringUTFChars(image_path, nullptr);
  const char* dp = env->GetStringUTFChars(destination, nullptr);
  ctx.image_path = ip ? ip : "";
  ctx.destination = dp ? dp : "";
  if (ip) env->ReleaseStringUTFChars(image_path, ip);
  if (dp) env->ReleaseStringUTFChars(destination, dp);
  ctx.listener = env->NewGlobalRef(listener);
  // Synchronous: the Kotlin side calls this from a background thread. The
  // listener callbacks are invoked from this (attached) thread.
  RunExtraction(std::move(ctx));
}
