// Save Queue as Playlist, from the player's ⋯ menu: the song playing and the songs queued after it (a Jam's too) put
// in a new private playlist. The player tells the app only the next two songs, so the queue is read from the Web
// API's player queue (the song playing and up to twenty after it) with the signed-in app's token (SGSpclientHeaders),
// and the playlist made and filled through the same API.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "PlayerSettings.h"

static void call(NSString *method, NSString *url, NSString *authorization, id body, void (^done)(id root, NSInteger status)) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = method;
    [request setValue:authorization forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (body) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (status < 200 || status >= 300) SGLog(@"save queue: %@ %@ answered %ld", method, url, (long)status);
        dispatch_async(dispatch_get_main_queue(), ^{ done(root, status); });
    }] resume];
}

static void tell(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static NSString *uriOf(id item) {
    return [item isKindOfClass:NSDictionary.class] && [item[@"uri"] isKindOfClass:NSString.class] ? item[@"uri"] : nil;
}

void SGSaveQueueAsPlaylist(void) {
    SGSpclientHeaders(^(NSDictionary<NSString *, NSString *> *headers) {
        NSString *authorization = headers[@"authorization"];
        if (!authorization) {
            tell(@"Couldn't save the queue", @"Spotify hasn't signed in yet. Try again in a moment.");
            return;
        }
        call(@"GET", @"https://api.spotify.com/v1/me/player/queue", authorization, nil, ^(id root, NSInteger status) {
            NSMutableArray<NSString *> *uris = [NSMutableArray array];
            NSString *playing = uriOf([root isKindOfClass:NSDictionary.class] ? root[@"currently_playing"] : nil);
            if (playing) [uris addObject:playing];
            for (id item in [root isKindOfClass:NSDictionary.class] && [root[@"queue"] isKindOfClass:NSArray.class] ? root[@"queue"] : @[]) {
                NSString *uri = uriOf(item);
                if ([uri hasPrefix:@"spotify:track:"] && ![uris containsObject:uri]) [uris addObject:uri];
            }
            if (!uris.count) {
                tell(@"Couldn't save the queue", status == 200 ? @"The queue is empty." : @"Spotify didn't give the queue out.");
                return;
            }
            NSDateFormatter *format = [NSDateFormatter new];
            format.dateStyle = NSDateFormatterMediumStyle;
            format.timeStyle = NSDateFormatterShortStyle;
            NSString *name = [NSString stringWithFormat:@"Queue, %@", [format stringFromDate:NSDate.date]];
            call(@"POST", @"https://api.spotify.com/v1/me/playlists", authorization,
                 @{@"name": name, @"public": @NO, @"description": @"Saved from the queue by Vitrine"}, ^(id made, NSInteger madeStatus) {
                NSString *playlist = [made isKindOfClass:NSDictionary.class] && [made[@"id"] isKindOfClass:NSString.class] ? made[@"id"] : nil;
                if (!playlist) {
                    tell(@"Couldn't save the queue", @"Spotify didn't make the playlist.");
                    return;
                }
                NSString *tracks = [NSString stringWithFormat:@"https://api.spotify.com/v1/playlists/%@/tracks", playlist];
                call(@"POST", tracks, authorization, @{@"uris": [uris subarrayWithRange:NSMakeRange(0, MIN(uris.count, 100))]}, ^(id added, NSInteger addedStatus) {
                    if (addedStatus >= 200 && addedStatus < 300) {
                        tell(@"Queue saved", [NSString stringWithFormat:@"%lu songs are in “%@” in Your Library.", (unsigned long)uris.count, name]);
                    } else {
                        tell(@"Couldn't save the queue", @"The playlist was made, but Spotify didn't take its songs.");
                    }
                });
            });
        });
    });
}
