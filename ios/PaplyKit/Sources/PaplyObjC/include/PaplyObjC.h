#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Führt `block` aus und fängt eine Objective-C-Ausnahme ab (z. B. von AVAudioEngine, wenn das
/// Tap-Format nach einem Anruf nicht zur Hardware passt). Swift kann solche Ausnahmen nicht
/// selbst fangen – ohne diesen Umweg beendet iOS die App. nil = keine Ausnahme.
FOUNDATION_EXPORT NSException * _Nullable PaplyCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
