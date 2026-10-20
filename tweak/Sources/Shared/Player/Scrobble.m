// Scrobbling to ListenBrainz and Last.fm. A song is sent as listened to once it has played half its length or four
// minutes, whichever is sooner, and not at all under thirty seconds, which is both services' rule; the song starting
// is sent as playing now. Plays that failed to send are tried again with the next one (up to kPending).
//
// ListenBrainz takes the user token from its settings page. Last.fm takes an API key and secret of the user's own
// (last.fm/api/account/create) and signs in once with the username and password, through auth.getMobileSession:
// only the session it answers with is kept, never the password. All of it lives in the Keychain, so a settings export
// carries none of it. Only the song, artist, album, length and the time go out.
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "PlayerSettings.h"
#import "PlayerState.h"

static NSString *const kLastFM = @"https://ws.audioscrobbler.com/2.0/";
static NSString *const kListenBrainz = @"https://api.listenbrainz.org/1/submit-listens";
static const NSUInteger kPending = 50;

#pragma mark - the Keychain

static NSDictionary *itemQuery(NSString *name) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: @"vitrine.scrobble", (__bridge id)kSecAttrAccount: name};
}

static NSString *secret(NSString *name) {
    NSMutableDictionary *query = [itemQuery(name) mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef data = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &data) != errSecSuccess || !data) return nil;
    return [[NSString alloc] initWithData:CFBridgingRelease(data) encoding:NSUTF8StringEncoding];
}

static void storeSecret(NSString *name, NSString *value) {
    SecItemDelete((__bridge CFDictionaryRef)itemQuery(name));
    if (!value.length) return;
    NSMutableDictionary *item = [itemQuery(name) mutableCopy];
    item[(__bridge id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

#pragma mark - sending

static NSString *md5(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);   // Last.fm's signature is MD5 by its spec
#pragma clang diagnostic pop
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSString *formEscaped(NSString *value) {
    NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
    [allowed addCharactersInString:@"-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

// A signed Last.fm call: every parameter but format in the signature, sorted by name, then the secret.
static void lastFM(NSDictionary<NSString *, NSString *> *params, NSString *apiSecret, void (^done)(id root, NSInteger status)) {
    NSMutableString *signed_ = [NSMutableString string];
    for (NSString *name in [params.allKeys sortedArrayUsingSelector:@selector(compare:)]) [signed_ appendFormat:@"%@%@", name, params[name]];
    [signed_ appendString:apiSecret];
    NSMutableDictionary *all = [params mutableCopy];
    all[@"api_sig"] = md5(signed_);
    all[@"format"] = @"json";
    NSMutableArray *pairs = [NSMutableArray array];
    [all enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", formEscaped(name), formEscaped(value)]];
    }];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLastFM]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(root, status); });
    }] resume];
}

static void listenBrainz(NSString *token, NSDictionary *body, void (^done)(NSInteger status)) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kListenBrainz]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Token " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{ done(status); });
    }] resume];
}

#pragma mark - a play

@interface SGScrobblePlay : NSObject
@property (nonatomic, copy) NSString *title, *artist, *album, *uri;
@property (nonatomic) NSInteger seconds, startedAt;
@end
@implementation SGScrobblePlay
@end

static BOOL lastFMOn(void) {
    return secret(@"lastfm.session").length && secret(@"lastfm.key").length && secret(@"lastfm.secret").length;
}

static void sendNowPlaying(SGScrobblePlay *play) {
    NSString *token = secret(@"listenbrainz.token");
    if (token.length) {
        listenBrainz(token, @{@"listen_type": @"playing_now", @"payload": @[@{@"track_metadata": @{
            @"artist_name": play.artist, @"track_name": play.title, @"release_name": play.album ?: @""}}]}, ^(NSInteger status) {});
    }
    if (lastFMOn()) {
        NSMutableDictionary *params = [@{@"method": @"track.updateNowPlaying", @"artist": play.artist, @"track": play.title,
                                         @"api_key": secret(@"lastfm.key"), @"sk": secret(@"lastfm.session")} mutableCopy];
        if (play.album.length) params[@"album"] = play.album;
        if (play.seconds > 0) params[@"duration"] = @(play.seconds).stringValue;
        lastFM(params, secret(@"lastfm.secret"), ^(id root, NSInteger status) {});
    }
}

static NSMutableArray<SGScrobblePlay *> *sg_pending;

static void sendListens(void) {
    NSArray<SGScrobblePlay *> *plays = [sg_pending copy];
    if (!plays.count) return;
    [sg_pending removeAllObjects];
    __block NSUInteger left = 0;
    NSMutableArray<SGScrobblePlay *> *failed = [NSMutableArray array];
    void (^settle)(NSArray<SGScrobblePlay *> *, BOOL) = ^(NSArray<SGScrobblePlay *> *sent, BOOL ok) {
        if (!ok) for (SGScrobblePlay *play in sent) if (![failed containsObject:play]) [failed addObject:play];
        if (--left == 0 && failed.count) {
            [sg_pending addObjectsFromArray:failed];
            while (sg_pending.count > kPending) [sg_pending removeObjectAtIndex:0];
            SGLog(@"scrobble: %lu plays kept to send again", (unsigned long)sg_pending.count);
        }
    };
    NSString *token = secret(@"listenbrainz.token");
    if (token.length) {
        left++;
        NSMutableArray *payload = [NSMutableArray array];
        for (SGScrobblePlay *play in plays) {
            [payload addObject:@{@"listened_at": @(play.startedAt), @"track_metadata": @{
                @"artist_name": play.artist, @"track_name": play.title, @"release_name": play.album ?: @"",
                @"additional_info": @{@"duration_ms": @(play.seconds * 1000), @"spotify_id": play.uri ?: @"",
                                      @"media_player": @"Spotify", @"submission_client": @"Vitrine"}}}];
        }
        listenBrainz(token, @{@"listen_type": plays.count > 1 ? @"import" : @"single", @"payload": payload}, ^(NSInteger status) {
            SGLog(@"scrobble: ListenBrainz took %lu plays: %ld", (unsigned long)plays.count, (long)status);
            settle(plays, status == 200);
        });
    }
    if (lastFMOn()) {
        left++;
        // Up to 50 a call, indexed: artist[0], track[0], timestamp[0]...
        NSMutableDictionary *params = [@{@"method": @"track.scrobble", @"api_key": secret(@"lastfm.key"),
                                         @"sk": secret(@"lastfm.session")} mutableCopy];
        [plays enumerateObjectsUsingBlock:^(SGScrobblePlay *play, NSUInteger i, BOOL *stop) {
            params[[NSString stringWithFormat:@"artist[%lu]", (unsigned long)i]] = play.artist;
            params[[NSString stringWithFormat:@"track[%lu]", (unsigned long)i]] = play.title;
            params[[NSString stringWithFormat:@"timestamp[%lu]", (unsigned long)i]] = @(play.startedAt).stringValue;
            if (play.album.length) params[[NSString stringWithFormat:@"album[%lu]", (unsigned long)i]] = play.album;
            if (play.seconds > 0) params[[NSString stringWithFormat:@"duration[%lu]", (unsigned long)i]] = @(play.seconds).stringValue;
        }];
        lastFM(params, secret(@"lastfm.secret"), ^(id root, NSInteger status) {
            BOOL ok = status == 200 && [root isKindOfClass:NSDictionary.class] && root[@"scrobbles"];
            SGLog(@"scrobble: Last.fm took %lu plays: %ld", (unsigned long)plays.count, (long)status);
            settle(plays, ok);
        });
    }
}

@interface SGScrobbler : NSObject <SGPlayerStateObserver>
@end

@implementation SGScrobbler {
    SGScrobblePlay *_play;
    double _heard;          // seconds of it played
    double _lastPosition;   // where it was at the last report
    BOOL _sent;
}

- (BOOL)enabled {
    return secret(@"listenbrainz.token").length || lastFMOn();
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (!_play || state.isPaused) {
        _lastPosition = state.position;
        return;
    }
    double step = state.position - _lastPosition;
    // Only the time it was heard: a seek is a jump, not listening.
    if (step > 0 && step < 5) _heard += step;
    _lastPosition = state.position;
    if (!_sent && _play.seconds >= 30 && (_heard >= _play.seconds / 2.0 || _heard >= 240)) {
        _sent = YES;
        if (!sg_pending) sg_pending = [NSMutableArray array];
        [sg_pending addObject:_play];
        sendListens();
    }
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    if (!uri || [uri isEqualToString:_play.uri]) return;
    _play = nil;
    if (![uri hasPrefix:@"spotify:track:"] && ![uri hasPrefix:@"spotify:local:"]) return;
    if (![self enabled] || !state.track.trackTitle.length || !state.track.artistName.length) return;
    SGScrobblePlay *play = [SGScrobblePlay new];
    play.uri = uri;
    play.title = state.track.trackTitle;
    play.artist = [state.track.artistName componentsSeparatedByString:@","].firstObject;
    id album = state.track.metadata[@"album_title"];
    play.album = [album isKindOfClass:NSString.class] ? album : nil;
    play.seconds = (NSInteger)round(state.duration);
    play.startedAt = (NSInteger)NSDate.date.timeIntervalSince1970;
    _play = play;
    _heard = 0;
    _lastPosition = state.position;
    _sent = NO;
    sendNowPlaying(play);
}

@end

__attribute__((constructor)) static void startScrobbler(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGScrobbler *scrobbler;
        scrobbler = [SGScrobbler new];
        SGAddPlayerStateObserver(scrobbler);
    });
}

#pragma mark - the rows

static void tell(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static UITextField *field(UIAlertController *alert, NSString *placeholder, BOOL hidden) {
    __block UITextField *made = nil;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = placeholder;
        f.secureTextEntry = hidden;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        made = f;
    }];
    return made;
}

static NSString *trimmed(UITextField *f) {
    return [f.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static void askListenBrainz(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ListenBrainz"
        message:@"Paste your user token from listenbrainz.org › Settings. It stays on this iPhone." preferredStyle:UIAlertControllerStyleAlert];
    UITextField *token = field(alert, @"User token", YES);
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (trimmed(token).length) storeSecret(@"listenbrainz.token", trimmed(token));
    }]];
    if (secret(@"listenbrainz.token").length) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            storeSecret(@"listenbrainz.token", nil);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static void askLastFM(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Last.fm"
        message:@"Your own API key and secret from last.fm/api/account/create, then your Last.fm sign-in. Only the session Last.fm gives back is kept, not your password."
        preferredStyle:UIAlertControllerStyleAlert];
    UITextField *key = field(alert, @"API key", NO), *apiSecret = field(alert, @"Shared secret", YES);
    UITextField *user = field(alert, @"Username", NO), *password = field(alert, @"Password", YES);
    key.text = secret(@"lastfm.key");
    apiSecret.text = secret(@"lastfm.secret");
    [alert addAction:[UIAlertAction actionWithTitle:@"Sign In" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *k = trimmed(key), *s = trimmed(apiSecret), *u = trimmed(user), *p = password.text ?: @"";
        if (!k.length || !s.length || !u.length || !p.length) {
            tell(@"Last.fm", @"All four are needed to sign in.");
            return;
        }
        lastFM(@{@"method": @"auth.getMobileSession", @"username": u, @"password": p, @"api_key": k}, s, ^(id root, NSInteger status) {
            id session = [root isKindOfClass:NSDictionary.class] ? root[@"session"] : nil;
            NSString *sessionKey = [session isKindOfClass:NSDictionary.class] && [session[@"key"] isKindOfClass:NSString.class] ? session[@"key"] : nil;
            if (!sessionKey) {
                NSString *message = [root isKindOfClass:NSDictionary.class] && [root[@"message"] isKindOfClass:NSString.class] ? root[@"message"] : @"Last.fm didn't sign in.";
                tell(@"Last.fm", message);
                return;
            }
            storeSecret(@"lastfm.key", k);
            storeSecret(@"lastfm.secret", s);
            storeSecret(@"lastfm.session", sessionKey);
            storeSecret(@"lastfm.user", u);
            tell(@"Last.fm", [NSString stringWithFormat:@"Scrobbling as %@.", u]);
        });
    }]];
    if (lastFMOn()) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Sign Out" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            for (NSString *name in @[@"lastfm.session", @"lastfm.user"]) storeSecret(name, nil);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

NSArray<SGModRow *> *SGScrobbleRows(void) {
    return @[
        SGStatActionRow(@"ListenBrainz", @"Your user token", ^NSString *{ return secret(@"listenbrainz.token").length ? @"On" : @"Off"; },
                        ^{ askListenBrainz(); }),
        SGStatActionRow(@"Last.fm", @"Your own API key and sign-in", ^NSString *{
            return lastFMOn() ? (secret(@"lastfm.user") ?: @"On") : @"Off";
        }, ^{ askLastFM(); }),
    ];
}
