// Save Queue as Playlist, from the player's ⋯ menu: the song playing and the songs queued after it (a Jam's too) put
// in a new private playlist. The player tells the app only the next two songs, so the queue is read from the Web
// API's player queue (the song playing and up to twenty after it) with the signed-in app's token (SGSpclientHeaders),
// and the playlist made and filled through the same API.
#import <objc/runtime.h>
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


// A probe for reading the queue the way its own page does, logged when Save Queue as Playlist finds the Web API's
// queue empty: every class with a _nextTracks or _queueState ivar, with its ivars and methods, and the queue page's
// service and data source, so the next build can read the queue from them.
static void logClass(Class cls) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned int i = 0; i < count; i++) [parts addObject:[NSString stringWithFormat:@"ivar %s %s", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: ""]];
    free(ivars);
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) [parts addObject:[NSString stringWithFormat:@"- %@", NSStringFromSelector(method_getName(methods[i]))]];
    free(methods);
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    for (unsigned int i = 0; i < count; i++) [parts addObject:[NSString stringWithFormat:@"@property %s %s", property_getName(properties[i]), property_getAttributes(properties[i])]];
    free(properties);
    NSMutableString *line = [NSMutableString string];
    NSUInteger part = 0;
    for (NSString *entry in parts) {
        if (line.length + entry.length > 700) {
            SGLog(@"queue probe: %s (%lu) %@", class_getName(cls), (unsigned long)++part, line);
            [line setString:@""];
        }
        [line appendFormat:@"%@ | ", entry];
    }
    SGLog(@"queue probe: %s (%lu) %@ super %s", class_getName(cls), (unsigned long)++part, line, class_getName(class_getSuperclass(cls)));
}

static void probeQueue(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        const char *name = class_getName(cls);
        BOOL named = strstr(name, "Queue_ViewImpl") && (strstr(name, "QueueService") || strstr(name, "DataSource") || strstr(name, "QueuedTracks"));
        BOOL holds = class_getInstanceVariable(cls, "_nextTracks") || class_getInstanceVariable(cls, "_queueState") || class_getInstanceVariable(cls, "nextTracks");
        if (named || holds) logClass(cls);
    }
    free(classes);
    // The queue page, when it is open: its table's data source and how many rows it has.
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in scene.windows) {
            SGForEachView(window, ^(UIView *v) {
                if (![v isKindOfClass:UITableView.class]) return;
                id source = ((UITableView *)v).dataSource;
                if (!source || !strstr(class_getName([source class]), "Queue")) return;
                UITableView *table = (UITableView *)v;
                NSMutableArray *rows = [NSMutableArray array];
                for (NSInteger section = 0; section < table.numberOfSections; section++) [rows addObject:@([table numberOfRowsInSection:section])];
                SGLog(@"queue probe: page table %@, rows by section %@", NSStringFromClass([source class]), rows);
            });
        }
    }
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
                probeQueue();
                tell(@"Couldn't save the queue yet", @"Spotify's queue isn't readable this way. Vitrine noted how the queue page holds it: please send Mod Settings › About › Share diagnostics, ideally with the queue page open when you tap Save Queue.");
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
