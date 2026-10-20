// A probe for true shuffle, nothing more: it changes nothing of Spotify's and only writes to the log (Share
// diagnostics, Mod Settings > About), so a plain random order can be designed from what the player really exposes.
//
// Spotify's weighted shuffle runs in its C++ core (the binary's "shuffle_algorithm" and its "scoring" pass). What
// the app sees is SPTPlayerState: the context, shufflingContext, and `future`, the tracks to come. Whether `future`
// holds the whole shuffled context or a window of it decides what a true shuffle can do, so the probe logs, at each
// track change while shuffle is on (the first 30): the context, how many tracks come next and the first ten of them
// with where each came from (the context, a hand queue, autoplay); and once, the player's methods that name
// shuffle, queue, context or play.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "PlayerState.h"

static const NSUInteger kReports = 30;

@interface SGShuffleProbe : NSObject <SGPlayerStateObserver>
@end

@implementation SGShuffleProbe {
    NSString *_lastTrack;
    NSUInteger _reports;
    BOOL _methodsLogged;
}

- (void)logMethodsOf:(id)player {
    if (_methodsLogged || !player) return;
    _methodsLogged = YES;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (Class cls = [player class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            NSString *lower = name.lowercaseString;
            if ([lower containsString:@"shuffl"] || [lower containsString:@"queue"] || [lower containsString:@"context"]
                || [lower hasPrefix:@"play"] || [lower containsString:@"skip"]) {
                [names addObject:[NSString stringWithFormat:@"%@ %@", NSStringFromClass(cls), name]];
            }
        }
        free(methods);
    }
    SGLog(@"shuffle probe: player %@ methods: %@", NSStringFromClass([player class]), [names componentsJoinedByString:@" | "]);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_lastTrack]) return;
    _lastTrack = track;
    if (!state.options.shufflingContext || _reports >= kReports) return;
    _reports++;
    [self logMethodsOf:SGKaraokePlayer()];
    NSMutableArray<NSString *> *next = [NSMutableArray array];
    NSUInteger shown = 0;
    for (id item in state.future) {
        if (shown++ >= 10) break;
        if (![item isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] && ![item respondsToSelector:@selector(URI)]) continue;
        SPTPlayerTrack *upcoming = item;
        NSString *provider = [upcoming respondsToSelector:@selector(provider)] ? upcoming.provider : @"?";
        [next addObject:[NSString stringWithFormat:@"%@ (%@)", SGURIString(upcoming.URI) ?: @"?", provider ?: @"?"]];
    }
    SGLog(@"shuffle probe: %@ in %@, %lu to come, %lu played; next %@", track, SGURIString(state.contextURI) ?: @"no context",
          (unsigned long)state.future.count, (unsigned long)state.reverse.count, [next componentsJoinedByString:@", "]);
}

@end

__attribute__((constructor)) static void startShuffleProbe(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGShuffleProbe *probe;
        probe = [SGShuffleProbe new];
        SGAddPlayerStateObserver(probe);
    });
}
