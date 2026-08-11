#import "SunPadCoreHost.h"
#import "SunPadDiagnostics.h"
#import "SunPadInputPipeEncoder.h"

#import <AVFAudio/AVFAudio.h>
#import <fcntl.h>
#import <sys/stat.h>

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>
#include <thread>

namespace fs = std::filesystem;

/* The ModernGekko runtime header is a C++ header; include it here only. */
#include "moderngekko/runtime.hpp"

#include "Core/Config/GraphicsSettings.h"
#include "Core/System.h"
#include "VideoCommon/PerformanceMetrics.h"
#include "VideoCommon/VideoConfig.h"

@interface SunPadCoreHost ()
- (void)applyAspectRatioMode:(SunPadAspectRatioMode)mode;
@end

@implementation SunPadCoreHost {
    CAMetalLayer *_layer;
    std::thread *_gameThread;
    std::atomic<bool> *_stopRequested;
    std::atomic<bool> *_starting;
    std::atomic<bool> *_running;
    std::mutex *_runtimeMutex;
    moderngekko::Runtime *_runtime;
    int _pipeFd;
    void (^_onError)(NSString *);
}

- (instancetype)initWithLayer:(CAMetalLayer *)layer {
    if ((self = [super init])) {
        _layer = layer;
        _pipeFd = -1;
        _gameThread = new std::thread();
        _stopRequested = new std::atomic<bool>(false);
        _starting = new std::atomic<bool>(false);
        _running = new std::atomic<bool>(false);
        _runtimeMutex = new std::mutex();
        _runtime = nullptr;
    }
    return self;
}

- (BOOL)isRunning {
    return _running->load();
}

- (void)startWithGameRoot:(NSString *)gameRoot
            discImagePath:(NSString *)discImagePath
               modulePath:(NSString *)modulePath
             userDirectory:(NSString *)userDirectory
                   onError:(void (^)(NSString *))onError {
    if (_running->load() || _starting->load() || _gameThread->joinable())
        return;
    _onError = [onError copy];
    *_stopRequested = false;
    *_starting = true;

    NSError *audioSessionError = nil;
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&audioSessionError];
    if (!audioSessionError)
        [audioSession setActive:YES error:&audioSessionError];
    if (audioSessionError)
        SunPadLog(@"audio session setup failed: %@", audioSessionError);
    else
        SunPadLog(@"audio session active route=%@", audioSession.currentRoute.outputs.firstObject.portType ?: @"none");

    NSString *pipeDir = [userDirectory stringByAppendingPathComponent:@"Pipes"];
    NSString *pipePath = [pipeDir stringByAppendingPathComponent:@"sunpad"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pipeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    // The runtime opens the FIFO read-only; recreate if a stale file exists.
    ::unlink(pipePath.fileSystemRepresentation);
    int fifoResult = ::mkfifo(pipePath.fileSystemRepresentation, 0666);
    SunPadLog(@"input pipe create result=%d errno=%d", fifoResult, fifoResult == 0 ? 0 : errno);

    // This is a dedicated virtual GameCube controller. Dolphin's pipe backend
    // is present in the iOS core, but it has no default bindings, so provide
    // its stable mapping before the runtime initializes controllers.
    NSString *configDirectory = [userDirectory stringByAppendingPathComponent:@"Config"];
    [[NSFileManager defaultManager] createDirectoryAtPath:configDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *padConfig =
        @"[GCPad1]\n"
         "Device = Pipe/0/sunpad\n"
         "Buttons/A = `Button A`\n"
         "Buttons/B = `Button B`\n"
         "Buttons/X = `Button X`\n"
         "Buttons/Y = `Button Y`\n"
         "Buttons/Z = `Button Z`\n"
         "Buttons/Start = `Button START`\n"
         "Main Stick/Up = `Axis MAIN Y -`\n"
         "Main Stick/Down = `Axis MAIN Y +`\n"
         "Main Stick/Left = `Axis MAIN X -`\n"
         "Main Stick/Right = `Axis MAIN X +`\n"
         "Main Stick/Calibration = 100.00\n"
         "C-Stick/Up = `Axis C Y -`\n"
         "C-Stick/Down = `Axis C Y +`\n"
         "C-Stick/Left = `Axis C X -`\n"
         "C-Stick/Right = `Axis C X +`\n"
         "C-Stick/Calibration = 100.00\n"
         "Triggers/L = `Axis L +`\n"
         "Triggers/R = `Axis R +`\n"
         "Triggers/L-Analog = `Axis L +`\n"
         "Triggers/R-Analog = `Axis R +`\n"
         "D-Pad/Up = `Button D_UP`\n"
         "D-Pad/Down = `Button D_DOWN`\n"
         "D-Pad/Left = `Button D_LEFT`\n"
         "D-Pad/Right = `Button D_RIGHT`\n";
    [padConfig writeToFile:[configDirectory stringByAppendingPathComponent:@"GCPadNew.ini"]
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];

    SunPadLog(@"runtime thread starting discImage=%d moduleExists=%d",
              discImagePath.length > 0,
              [[NSFileManager defaultManager] fileExistsAtPath:modulePath]);
    *_gameThread = std::thread([self, gameRoot, discImagePath, modulePath, userDirectory] {
        [self runGameWithGameRoot:gameRoot
                    discImagePath:discImagePath
                       modulePath:modulePath
                    userDirectory:userDirectory];
    });
}

- (void)runGameWithGameRoot:(NSString *)gameRoot
              discImagePath:(NSString *)discImagePath
                 modulePath:(NSString *)modulePath
              userDirectory:(NSString *)userDirectory {
    std::string errorMessage;
    @autoreleasepool {
        moderngekko::RuntimeConfig config;
        config.game_root = gameRoot.fileSystemRepresentation;
        if (discImagePath.length > 0)
            config.disc_image = discImagePath.fileSystemRepresentation;
        config.user_directory = userDirectory.fileSystemRepresentation;
        config.graphics.backend = "Metal";
        config.headless = false;
        config.show_fps_in_title = false;
        config.enable_gmse01_60fps =
            [NSProcessInfo.processInfo.arguments containsObject:@"-sunpadExperimental60FPS"];
        config.render_surface = (__bridge void *)_layer;
        config.module = moderngekko::ModuleSource::DynamicPath(
            modulePath.fileSystemRepresentation);

        SunPadLog(@"runtime frame mode=%@ source=%@",
                  config.enable_gmse01_60fps ? @"60 FPS experimental" : @"original 30 FPS",
                  config.enable_gmse01_60fps ? @"launch argument" : @"default");

        auto created = moderngekko::Runtime::Create(std::move(config));
        if (!created) {
            errorMessage = created.error->message;
            *_starting = false;
            SunPadLog(@"runtime create failed: %s", errorMessage.c_str());
            if (_onError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    _onError(@(errorMessage.c_str()));
                });
            }
            return;
        }
        {
            std::scoped_lock lock(*_runtimeMutex);
            _runtime = created.runtime.get();
        }
        if (_stopRequested->load()) {
            std::scoped_lock lock(*_runtimeMutex);
            _runtime = nullptr;
            *_starting = false;
            return;
        }
        *_starting = false;
        *_running = true;
        SunPadLog(@"runtime created");

        // Apply the persisted render-resolution choice now that the runtime's
        // config layers exist.
        NSNumber *savedScaleValue =
            [[NSUserDefaults standardUserDefaults] objectForKey:@"SunPadRenderScale"];
        NSInteger savedScale = savedScaleValue ? savedScaleValue.integerValue : 1;
        Config::SetCurrent(Config::GFX_EFB_SCALE,
                           static_cast<int>(savedScale < 1 ? 1 : (savedScale > 4 ? 4 : savedScale)));
        Config::SetCurrent(Config::GFX_MAX_EFB_SCALE, 12);

        NSNumber *savedAspectValue = [[NSUserDefaults standardUserDefaults]
            objectForKey:@"SunPadAspectRatioMode"];
        SunPadAspectRatioMode savedAspect = savedAspectValue ?
            (SunPadAspectRatioMode)savedAspectValue.integerValue : SunPadAspectRatioOriginal;
        [self applyAspectRatioMode:savedAspect];

        // Open the input FIFO for writing (blocks until the runtime reads it).
        NSString *pipePath = [[userDirectory stringByAppendingPathComponent:@"Pipes"]
            stringByAppendingPathComponent:@"sunpad"];
        for (int attempt = 0; attempt < 600 && !_stopRequested->load(); ++attempt) {
            _pipeFd = ::open(pipePath.fileSystemRepresentation, O_WRONLY | O_NONBLOCK);
            if (_pipeFd >= 0) {
                SunPadLog(@"input pipe connected attempt=%d", attempt + 1);
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        if (_pipeFd < 0)
            SunPadLog(@"input pipe unavailable after wait errno=%d stopRequested=%d", errno,
                      _stopRequested->load());

        auto result = created.runtime->Run();
        {
            std::scoped_lock lock(*_runtimeMutex);
            _runtime = nullptr;
        }
        SunPadLog(@"runtime exited error=%d stopRequested=%d",
                  (bool)result.error, _stopRequested->load());
        if (result.error && _onError) {
            errorMessage = result.error->message;
            dispatch_async(dispatch_get_main_queue(), ^{
                _onError(@(errorMessage.c_str()));
            });
        }
        if (_pipeFd >= 0) {
            ::close(_pipeFd);
            _pipeFd = -1;
        }
    }
    *_running = false;
    *_starting = false;
}

- (void)publishInput:(SunPadInputState)input {
    if (_pipeFd < 0)
        return;
    static uint16_t lastButtons = 0;
    BOOL modernCStick = [SunPadSettings sharedSettings].modernCStickHorizontal;
    std::string commands = SunPadEncodePipeCommands(input, lastButtons, modernCStick);
    if (!commands.empty()) {
        ssize_t written = ::write(_pipeFd, commands.data(), commands.size());
        if (written == static_cast<ssize_t>(commands.size())) {
            // Advance edge tracking only after the whole atomic FIFO message
            // is delivered; an EAGAIN will retry the same button transition.
            lastButtons = input.buttons;
        } else if (written < 0 && errno != EAGAIN) {
            SunPadLog(@"input pipe write failed errno=%d bytes=%lu", errno,
                      (unsigned long)commands.size());
        } else if (written >= 0) {
            SunPadLog(@"input pipe partial write bytes=%ld expected=%lu", (long)written,
                      (unsigned long)commands.size());
        }
    }
}

- (void)setRenderScale:(NSInteger)scale {
    NSInteger clamped = scale < 1 ? 1 : (scale > 4 ? 4 : scale);
    if (!_running->load())
        return; // Runtime not booted yet; the scale applies at boot.
    // Config::SetCurrent is mutex-protected and the video backend refreshes
    // g_ActiveConfig on the next config callback.
    Config::SetCurrent(Config::GFX_EFB_SCALE, static_cast<int>(clamped));
}

- (void)applyAspectRatioMode:(SunPadAspectRatioMode)mode {
    switch (mode) {
    case SunPadAspectRatioWidescreen:
        Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::ForceWide);
        Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, true);
        break;
    case SunPadAspectRatioFillScreen: {
        CGSize size = _layer.drawableSize;
        int width = MAX(1, (int)std::lround(size.width));
        int height = MAX(1, (int)std::lround(size.height));
        Config::SetCurrent(Config::GFX_CUSTOM_ASPECT_RATIO_WIDTH, width);
        Config::SetCurrent(Config::GFX_CUSTOM_ASPECT_RATIO_HEIGHT, height);
        Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::CustomStretch);
        Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, true);
        break;
    }
    case SunPadAspectRatioOriginal:
    default:
        Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::ForceStandard);
        Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, false);
        break;
    }
}

- (void)setAspectRatioMode:(SunPadAspectRatioMode)mode {
    if (!_running->load())
        return; // Runtime not booted yet; the mode applies at boot.
    [self applyAspectRatioMode:mode];
}

- (double)currentFPS {
    if (!_running->load())
        return 0.0;
    return Core::System::GetInstance().GetPerfMetrics().GetFPS();
}

- (double)currentSpeed {
    if (!_running->load())
        return 0.0;
    return Core::System::GetInstance().GetPerfMetrics().GetSpeed();
}

- (NSString *)efbResolution {
    if (!_running->load())
        return @"";
    auto &metrics = Core::System::GetInstance().GetPerfMetrics();
    return [NSString stringWithFormat:@"%ux%u", metrics.GetEFBWidth(),
                                      metrics.GetEFBHeight()];
}

- (void)stop {
    SunPadLog(@"runtime stop requested starting=%d running=%d",
              _starting->load(), _running->load());
    *_stopRequested = true;
    {
        std::scoped_lock lock(*_runtimeMutex);
        if (_runtime != nullptr)
            _runtime->RequestStop();
    }
    if (_gameThread->joinable())
        _gameThread->join();
    *_starting = false;
    *_running = false;
}

- (void)restartWithGameRoot:(NSString *)gameRoot
              discImagePath:(NSString *)discImagePath
                 modulePath:(NSString *)modulePath {
    if (_gameThread->joinable()) {
        [self stop];
    }
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *userDirectory = [paths.firstObject stringByAppendingPathComponent:@"SunPad"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    __weak SunPadCoreHost *weakSelf = self;
    [self startWithGameRoot:gameRoot
              discImagePath:discImagePath
                 modulePath:modulePath
              userDirectory:userDirectory
                    onError:^(NSString *message) {
        (void)weakSelf;
        NSLog(@"[SunPad] runtime error after restart: %@", message);
    }];
}

- (void)dealloc {
    if (_gameThread->joinable())
        [self stop];
    if (_pipeFd >= 0)
        ::close(_pipeFd);
    delete _gameThread;
    delete _stopRequested;
    delete _starting;
    delete _running;
    delete _runtimeMutex;
}

@end
