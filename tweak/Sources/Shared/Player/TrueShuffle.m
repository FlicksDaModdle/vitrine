// True shuffle: a playlist in a plain random order, every order as likely as any other, in place of Spotify's
// weighted one (its C++ core scores tracks, so a playlist's familiar or "fitting" songs come round more often).
//
// When shuffle comes on for a playlist (the button, or a playlist started shuffled), the playlist's tracks are
// read as the app reads them (spclient's playlist/v2, with the signed-in app's headers, SGSpclientHeaders), put
// in a Fisher-Yates order with the song playing first, and played again as the same playlist with that order as
// its page and Spotify's own shuffle overridden off, from where the song was. Spotify's shuffle button reads off
// then, and turning it on again deals a new order.
//
// The parts, read off Spotify 9.1.90 by Shared/Player/ShuffleProbe.m: +[SPTPlayerTrack trackWithURI:],
// SPTPlayerContextPage's tracks, +[SPTPlayerContext contextForURI:] and its pages, SPTPlayOptions' seekTo and
// playerOptionsOverride (SPTPlayerOptionOverrides' shufflingContext), and -[SPTEsperantoPlayer playContext:options:].
// A play is checked a few seconds on against the tracks Spotify says come next; a context Spotify loaded again
// from its URI instead of taking the page is played once more as a context of the tracks alone.
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "PlayerSettings.h"
#import "PlayerState.h"

static NSString *const kPlaylist = @"https://spclient.wg.spotify.com/playlist/v2/playlist/";
static const NSTimeInterval kCheckAfter = 3;

// Every track URI in the playlist's protobuf, in its order: the items' URIs are plain strings in it.
static NSArray<NSString *> *trackURIsIn(NSData *data) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!text) return @[];
    static NSRegularExpression *uri;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        uri = [NSRegularExpression regularExpressionWithPattern:@"spotify:(track|episode):[0-9A-Za-z]{22}" options:0 error:nil];
    });
    NSMutableArray<NSString *> *uris = [NSMutableArray array];
    for (NSTextCheckingResult *match in [uri matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        [uris addObject:[text substringWithRange:match.range]];
    }
    return uris;
}

static void fetchPlaylist(NSString *playlistID, void (^done)(NSArray<NSString *> *uris)) {
    SGSpclientHeaders(^(NSDictionary<NSString *, NSString *> *headers) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[kPlaylist stringByAppendingString:playlistID]]];
        [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
            [request setValue:value forHTTPHeaderField:name];
        }];
        [request setValue:@"application/x-protobuf" forHTTPHeaderField:@"Accept"];
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            NSArray<NSString *> *uris = status == 200 && data ? trackURIsIn(data) : @[];
            SGLog(@"true shuffle: playlist %@ answered %ld, %lu bytes, %lu tracks%@", playlistID, (long)status,
                  (unsigned long)data.length, (unsigned long)uris.count, error ? [@", " stringByAppendingString:error.localizedDescription] : @"");
            dispatch_async(dispatch_get_main_queue(), ^{ done(uris); });
        }] resume];
    });
}

// Fisher-Yates, `first` (the song playing) kept at the front.
static NSArray<NSString *> *dealt(NSArray<NSString *> *uris, NSString *first) {
    NSMutableArray<NSString *> *rest = [uris mutableCopy];
    NSUInteger at = first ? [rest indexOfObject:first] : NSNotFound;
    if (at != NSNotFound) [rest removeObjectAtIndex:at];
    for (NSUInteger i = rest.count; i > 1; i--) {
        [rest exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
    }
    if (at != NSNotFound) [rest insertObject:first atIndex:0];
    return rest;
}

static id makeTrack(NSString *uri) {
    Class cls = NSClassFromString(@"SPTPlayerTrack");
    NSURL *url = [NSURL URLWithString:uri];
    if (!cls || !url || ![cls respondsToSelector:NSSelectorFromString(@"trackWithURI:")]) return nil;
    return ((id (*)(Class, SEL, NSURL *))objc_msgSend)(cls, NSSelectorFromString(@"trackWithURI:"), url);
}

// The playlist as a context of `order`: under its own URI, or (withURI NO) of the tracks alone.
static id makeContext(NSString *contextURI, NSArray<NSString *> *order, BOOL withURI) {
    Class contextClass = NSClassFromString(@"SPTPlayerContext"), pageClass = NSClassFromString(@"SPTPlayerContextPage");
    if (!contextClass || !pageClass) return nil;
    NSMutableArray *tracks = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *uri in order) {
        id track = makeTrack(uri);
        if (track) [tracks addObject:track];
    }
    if (!tracks.count) return nil;
    if (!withURI) {
        if (![contextClass respondsToSelector:NSSelectorFromString(@"contextWithTracks:")]) return nil;
        return ((id (*)(Class, SEL, NSArray *))objc_msgSend)(contextClass, NSSelectorFromString(@"contextWithTracks:"), tracks);
    }
    NSURL *url = [NSURL URLWithString:contextURI];
    if (!url || ![contextClass respondsToSelector:NSSelectorFromString(@"contextForURI:")]) return nil;
    id context = ((id (*)(Class, SEL, NSURL *))objc_msgSend)(contextClass, NSSelectorFromString(@"contextForURI:"), url);
    id page = [pageClass new];
    if (![page respondsToSelector:NSSelectorFromString(@"setTracks:")] || ![context respondsToSelector:NSSelectorFromString(@"setPages:")]) return nil;
    ((void (*)(id, SEL, NSArray *))objc_msgSend)(page, NSSelectorFromString(@"setTracks:"), tracks);
    ((void (*)(id, SEL, NSArray *))objc_msgSend)(context, NSSelectorFromString(@"setPages:"), @[page]);
    return context;
}

// Play from where the song is, Spotify's shuffle off and its repeat as it was.
static id makeOptions(SPTPlayerState *state, NSInteger seekMs) {
    Class optionsClass = NSClassFromString(@"SPTPlayOptions"), overridesClass = NSClassFromString(@"SPTPlayerOptionOverrides");
    if (!optionsClass || !overridesClass) return nil;
    id options = [optionsClass new], overrides = [overridesClass new];
    ((void (*)(id, SEL, NSNumber *))objc_msgSend)(overrides, NSSelectorFromString(@"setShufflingContext:"), @NO);
    ((void (*)(id, SEL, NSNumber *))objc_msgSend)(overrides, NSSelectorFromString(@"setRepeatingContext:"), @(state.options.repeatingContext));
    ((void (*)(id, SEL, id))objc_msgSend)(options, NSSelectorFromString(@"setPlayerOptionsOverride:"), overrides);
    if (seekMs > 0) ((void (*)(id, SEL, NSNumber *))objc_msgSend)(options, NSSelectorFromString(@"setSeekTo:"), @(seekMs));
    if (state.isPaused && [options respondsToSelector:NSSelectorFromString(@"setInitiallyPaused:")]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(options, NSSelectorFromString(@"setInitiallyPaused:"), YES);
    }
    return options;
}

static NSInteger positionMs(SPTPlayerState *state) {
    double position = state.positionAsOfTimestamp;
    if (!state.isPaused && state.timestamp) position += -state.timestamp.timeIntervalSinceNow * (state.playbackSpeed > 0 ? state.playbackSpeed : 1);
    return (NSInteger)(MAX(0, position) * 1000);
}

@interface SGTrueShuffle : NSObject <SGPlayerStateObserver>
@end

@implementation SGTrueShuffle {
    BOOL _wasShuffling;
    NSString *_lastContext;
    BOOL _busy;
}

- (BOOL)play:(NSString *)contextURI order:(NSArray<NSString *> *)order withURI:(BOOL)withURI {
    id player = SGKaraokePlayer();
    SPTPlayerState *state = SGPlayerState();
    id context = makeContext(contextURI, order, withURI), options = state ? makeOptions(state, positionMs(state)) : nil;
    SEL play = NSSelectorFromString(@"playContext:options:");
    if (!player || !context || !options || ![player respondsToSelector:play]) {
        SGLog(@"true shuffle: could not build the play (player %d, context %d, options %d)", player != nil, context != nil, options != nil);
        return NO;
    }
    ((id (*)(id, SEL, id, id))objc_msgSend)(player, play, context, options);
    SGLog(@"true shuffle: %@ dealt %lu tracks%@, next %@", contextURI, (unsigned long)order.count,
          withURI ? @"" : @" as a context of tracks", order.count > 1 ? order[1] : @"none");
    return YES;
}

// Whether Spotify plays the order: the track it says comes next is the one dealt second.
- (void)check:(NSString *)contextURI order:(NSArray<NSString *> *)order withURI:(BOOL)withURI {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCheckAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPTPlayerState *state = SGPlayerState();
        NSString *next = nil;
        for (id item in state.future) {
            if ([item respondsToSelector:@selector(URI)]) { next = SGURIString([item URI]); break; }
        }
        NSUInteger at = next ? [order indexOfObject:next] : NSNotFound;
        BOOL followed = at != NSNotFound && at <= 2;
        SGLog(@"true shuffle: next is %@ (%@)", next ?: @"nothing", followed ? @"the dealt order" : @"not the dealt order");
        if (!followed && withURI && order.count > 1) {
            if ([self play:contextURI order:order withURI:NO]) [self check:contextURI order:order withURI:NO];
            return;
        }
        self->_busy = NO;
    });
}

- (void)dealFor:(NSString *)contextURI track:(NSString *)track {
    _busy = YES;
    NSString *playlistID = [contextURI componentsSeparatedByString:@":"].lastObject;
    fetchPlaylist(playlistID, ^(NSArray<NSString *> *uris) {
        if (uris.count < 3) {
            SGLog(@"true shuffle: %@ has %lu tracks to deal; Spotify's shuffle stays", contextURI, (unsigned long)uris.count);
            self->_busy = NO;
            return;
        }
        NSArray<NSString *> *order = dealt(uris, track);
        if ([self play:contextURI order:order withURI:YES]) [self check:contextURI order:order withURI:YES];
        else self->_busy = NO;
    });
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!state) return;
    BOOL shuffling = state.options.shufflingContext;
    NSString *context = SGURIString(state.contextURI);
    BOOL turnedOn = shuffling && (!_wasShuffling || ![context isEqualToString:_lastContext]);
    _wasShuffling = shuffling;
    _lastContext = context;
    if (!turnedOn || _busy || !SGEnabled(SGKeyTrueShuffle)) return;
    if (![context hasPrefix:@"spotify:playlist:"]) {
        SGLog(@"true shuffle: %@ is not a playlist; Spotify's shuffle stays", context ?: @"no context");
        return;
    }
    [self dealFor:context track:SGURIString(state.track.URI)];
}

@end

__attribute__((constructor)) static void startTrueShuffle(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGTrueShuffle *shuffle;
        shuffle = [SGTrueShuffle new];
        SGAddPlayerStateObserver(shuffle);
    });
}
