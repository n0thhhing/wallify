#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <dlfcn.h>

typedef void (*MRRegisterNotificationsFn)(dispatch_queue_t);

// These notification resources intentionally live for the process lifetime; initialization is guarded by dispatch_once.
static dispatch_semaphore_t g_metadata_notification_semaphore;
static id g_infoObserver;
static id g_playingObserver;
static id g_appObserver;

static void metadataNotificationsInitOnMain(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_metadata_notification_semaphore = dispatch_semaphore_create(0);

        // Keep MediaRemote loaded for the duration of the helper process; unloading while callbacks are registered would be unsafe.
        void* handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (handle) {
            MRRegisterNotificationsFn registerFn =
                (MRRegisterNotificationsFn)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
            if (registerFn)
                registerFn(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        }

        NSNotificationCenter* center = [NSNotificationCenter defaultCenter];

        g_infoObserver = [center addObserverForName:
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification"
            object:nil
            queue:nil
            usingBlock:^(NSNotification* notification) {
                (void)notification;
                dispatch_semaphore_signal(g_metadata_notification_semaphore);
            }];

        g_playingObserver = [center addObserverForName:
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
            object:nil
            queue:nil
            usingBlock:^(NSNotification* notification) {
                (void)notification;
                dispatch_semaphore_signal(g_metadata_notification_semaphore);
            }];

        g_appObserver = [center addObserverForName:
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
            object:nil
            queue:nil
            usingBlock:^(NSNotification* notification) {
                (void)notification;
                dispatch_semaphore_signal(g_metadata_notification_semaphore);
            }];
    });
}

void mrc_notifications_init(void) {
    if ([NSThread isMainThread]) {
        metadataNotificationsInitOnMain();
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            metadataNotificationsInitOnMain();
        });
    }
}

int mrc_wait_for_notification(void) {
    if (!g_metadata_notification_semaphore)
        return 0;

    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 2000 * NSEC_PER_MSEC);
    return dispatch_semaphore_wait(g_metadata_notification_semaphore, timeout) == 0 ? 1 : 0;
}
