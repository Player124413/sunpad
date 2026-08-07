#import "SunPadCoreHost.h"

#import <AVFAudio/AVFAudio.h>
#import <fcntl.h>
#import <sys/stat.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>
#include <thread>

namespace fs = std::filesystem;

/* The ModernGekko runtime header is a C++ header; include it here only. */
#include "moderngekko/runtime.hpp"

#include "Core/Config/GraphicsSettings.h"
#include "Core/System.h"
#include "VideoCommon/PerformanceMetrics.h"

@implementation SunPadCoreHost {
    CAMetalLayer *_layer;
    std::thread *_gameThread;
    std::atomic<bool> *_stopRequested;
    std::atomic<bool> *_running;
    int _pipeFd;
    void (^_onError)(NSString *);
}

- (instancetype)initWithLayer:(CAMetalLayer *)layer {
    if ((self = [super init])) {
        _layer = layer;
        _pipeFd = -1;
        _gameThread = new std::thread();
        _stopRequested = new std::atomic<bool>(false);
        _running = new std::atomic<bool>(false);
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
    if (_running->load())
        return;
    _onError = [onError copy];
    *_stopRequested = false;

    NSError *audioSessionError = nil;
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&audioSessionError];
    if (!audioSessionError)
        [audioSession setActive:YES error:&audioSessionError];
    if (audioSessionError)
        NSLog(@"[SunPad] audio session setup failed: %@", audioSessionError);

    NSString *pipeDir = [userDirectory stringByAppendingPathComponent:@"Pipes"];
    NSString *pipePath = [pipeDir stringByAppendingPathComponent:@"sunpad"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pipeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    // The runtime opens the FIFO read-only; recreate if a stale file exists.
    ::unlink(pipePath.fileSystemRepresentation);
    ::mkfifo(pipePath.fileSystemRepresentation, 0666);

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
        config.render_surface = (__bridge void *)_layer;
        config.module = moderngekko::ModuleSource::DynamicPath(
            modulePath.fileSystemRepresentation);

        auto created = moderngekko::Runtime::Create(std::move(config));
        if (!created) {
            errorMessage = created.error->message;
            if (_onError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    _onError(@(errorMessage.c_str()));
                });
            }
            return;
        }
        *_running = true;

        // Apply the persisted render-resolution choice now that the runtime's
        // config layers exist.
        NSNumber *savedScaleValue =
            [[NSUserDefaults standardUserDefaults] objectForKey:@"SunPadRenderScale"];
        NSInteger savedScale = savedScaleValue ? savedScaleValue.integerValue : 1;
        Config::SetCurrent(Config::GFX_EFB_SCALE,
                           static_cast<int>(savedScale < 1 ? 1 : (savedScale > 4 ? 4 : savedScale)));
        Config::SetCurrent(Config::GFX_MAX_EFB_SCALE, 12);

        // Open the input FIFO for writing (blocks until the runtime reads it).
        NSString *pipePath = [[userDirectory stringByAppendingPathComponent:@"Pipes"]
            stringByAppendingPathComponent:@"sunpad"];
        for (int attempt = 0; attempt < 600 && !_stopRequested->load(); ++attempt) {
            _pipeFd = ::open(pipePath.fileSystemRepresentation, O_WRONLY | O_NONBLOCK);
            if (_pipeFd >= 0)
                break;
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        auto result = created.runtime->Run();
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
}

- (void)publishInput:(SunPadInputState)input {
    if (_pipeFd < 0)
        return;
    char buffer[128];
    int len = 0;
    // Sticks are int8 [-127,127]; the pipe expects raw [0,1] with 0.5 neutral
    // and the positive Y axis mapped to stick-down (GCPadNew.ini).
    float mx = 0.5f + (input.stickX / 127.0f) * 0.5f;
    float my = 0.5f - (input.stickY / 127.0f) * 0.5f;
    float cx = 0.5f + (input.cStickX / 127.0f) * 0.5f;
    float cy = 0.5f - (input.cStickY / 127.0f) * 0.5f;
    len += snprintf(buffer + len, sizeof(buffer) - len,
                    "SET MAIN %.3f %.3f\n", mx, my);
    len += snprintf(buffer + len, sizeof(buffer) - len,
                    "SET C %.3f %.3f\n", cx, cy);
    // Triggers are uint8 [0,255] -> pipe value [0,1] (0 = off, 1 = full).
    len += snprintf(buffer + len, sizeof(buffer) - len,
                    "SET L %.3f\n", input.triggerL / 255.0f);
    len += snprintf(buffer + len, sizeof(buffer) - len,
                    "SET R %.3f\n", input.triggerR / 255.0f);

    struct { uint16_t bit; const char *name; } buttons[] = {
        {SunPadButtonA, "A"},    {SunPadButtonB, "B"},
        {SunPadButtonX, "X"},    {SunPadButtonY, "Y"},
        {SunPadButtonZ, "Z"},    {SunPadButtonStart, "START"},
        {SunPadButtonL, "L"},    {SunPadButtonR, "R"},
        {SunPadButtonDpadUp, "D_UP"},
        {SunPadButtonDpadDown, "D_DOWN"},
        {SunPadButtonDpadLeft, "D_LEFT"},
        {SunPadButtonDpadRight, "D_RIGHT"},
    };
    static uint16_t lastButtons = 0;
    for (const auto &button : buttons) {
        bool pressed = (input.buttons & button.bit) != 0;
        bool wasPressed = (lastButtons & button.bit) != 0;
        if (pressed && !wasPressed)
            len += snprintf(buffer + len, sizeof(buffer) - len,
                            "PRESS %s\n", button.name);
        else if (!pressed && wasPressed)
            len += snprintf(buffer + len, sizeof(buffer) - len,
                            "RELEASE %s\n", button.name);
    }
    lastButtons = input.buttons;

    if (len > 0)
        ::write(_pipeFd, buffer, len);
}

- (void)setRenderScale:(NSInteger)scale {
    NSInteger clamped = scale < 1 ? 1 : (scale > 4 ? 4 : scale);
    if (!_running->load())
        return; // Runtime not booted yet; the scale applies at boot.
    // Config::SetCurrent is mutex-protected and the video backend refreshes
    // g_ActiveConfig on the next config callback.
    Config::SetCurrent(Config::GFX_EFB_SCALE, static_cast<int>(clamped));
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
    *_stopRequested = true;
    if (_gameThread->joinable())
        _gameThread->join();
}

- (void)restartWithGameRoot:(NSString *)gameRoot
              discImagePath:(NSString *)discImagePath
                 modulePath:(NSString *)modulePath {
    if (*_running) {
        // Graceful stop; the runtime's Run returns and the thread joins.
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
    if (_pipeFd >= 0)
        ::close(_pipeFd);
    if (_gameThread->joinable())
        _gameThread->join();
    delete _gameThread;
    delete _stopRequested;
    delete _running;
}

@end
