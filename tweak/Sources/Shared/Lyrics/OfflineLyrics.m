// Lyrics kept on the phone: every song's lines the engine keeps (from any source, Spotify's own included) are written
// to Caches/Vitrine/OfflineLyrics, words and times and all, and a song that plays again without them (no network,
// a source down) gets them back from there a few seconds into it. The newest kMaxSongs are kept.
//
// The lines are written as they were kept, pronunciations and translations left out (those are found again, and the
// saved translations have their own store, SavedTranslations.m). Reading and writing happen off the main queue.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Lyrics.h"

static const NSUInteger kMaxSongs = 1000;
static const NSTimeInterval kRestoreAfter = 4;

static NSURL *folder(void) {
    static NSURL *url;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        url = [caches URLByAppendingPathComponent:@"Vitrine/OfflineLyrics" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return url;
}

static NSURL *fileFor(NSString *track) {
    NSString *name = [track stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
    return name.length ? [folder() URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]] : nil;
}

static dispatch_queue_t disk(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("vitrine.offlineLyrics", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSDictionary *lineOut(SGKaraokeLine *line) {
    NSMutableArray *words = [NSMutableArray arrayWithCapacity:line.words.count];
    for (SGKaraokeWord *word in line.words) {
        [words addObject:@{@"t": word.text ?: @"", @"s": @(word.start), @"e": @(word.end), @"j": @(word.joined)}];
    }
    NSMutableDictionary *out = [@{@"s": @(line.start), @"e": @(line.end), @"timing": @(line.timing), @"align": @(line.align),
                                  @"words": words} mutableCopy];
    if (line.voice) out[@"voice"] = line.voice;
    if (line.backing) out[@"backing"] = lineOut(line.backing);
    return out;
}

static SGKaraokeLine *lineIn(NSDictionary *saved) {
    if (![saved isKindOfClass:NSDictionary.class]) return nil;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.start = [saved[@"s"] integerValue];
    line.end = [saved[@"e"] integerValue];
    line.timing = [saved[@"timing"] unsignedIntegerValue];
    line.align = [saved[@"align"] unsignedIntegerValue];
    if ([saved[@"voice"] isKindOfClass:NSString.class]) line.voice = saved[@"voice"];
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (NSDictionary *w in [saved[@"words"] isKindOfClass:NSArray.class] ? saved[@"words"] : @[]) {
        if (![w isKindOfClass:NSDictionary.class]) continue;
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = [w[@"t"] isKindOfClass:NSString.class] ? w[@"t"] : @"";
        word.start = [w[@"s"] integerValue];
        word.end = [w[@"e"] integerValue];
        word.joined = [w[@"j"] boolValue];
        [words addObject:word];
    }
    line.words = words;
    if (saved[@"backing"]) line.backing = lineIn(saved[@"backing"]);
    return line;
}

// Oldest out once there are too many, checked every so often rather than on every write.
static void trim(void) {
    static NSUInteger writes;
    if (++writes % 50) return;
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder() includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    if (files.count <= kMaxSongs) return;
    files = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *da = nil, *db = nil;
        [a getResourceValue:&da forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&db forKey:NSURLContentModificationDateKey error:nil];
        return [da ?: NSDate.distantPast compare:db ?: NSDate.distantPast];
    }];
    for (NSUInteger i = 0; i + kMaxSongs < files.count; i++) [NSFileManager.defaultManager removeItemAtURL:files[i] error:nil];
}

void SGOfflineLyricsSave(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    NSURL *url = fileFor(track);
    if (!url || lines.count < 2) return;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [out addObject:lineOut(line)];
    dispatch_async(disk(), ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"lines": out} options:0 error:nil];
        [data writeToURL:url atomically:YES];
        trim();
    });
}

static void restore(NSString *track) {
    NSURL *url = fileFor(track);
    if (!url) return;
    dispatch_async(disk(), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
        for (NSDictionary *saved in [root isKindOfClass:NSDictionary.class] && [root[@"lines"] isKindOfClass:NSArray.class] ? root[@"lines"] : @[]) {
            SGKaraokeLine *line = lineIn(saved);
            if (line) [lines addObject:line];
        }
        if (lines.count < 2) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (SGKaraokeLinesForTrack(track).count) return;   // they came after all
            SGLog(@"offline lyrics: %lu lines of %@ from the phone", (unsigned long)lines.count, track);
            SGKaraokeKeepLines(track, lines);
        });
    });
}

@interface SGOfflineLyrics : NSObject <SGPlayerStateObserver>
@end

@implementation SGOfflineLyrics {
    NSString *_track;
}
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGKaraokePlayingTrack();
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRestoreAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([SGKaraokePlayingTrack() isEqualToString:track] && !SGKaraokeLinesForTrack(track).count) restore(track);
    });
}
@end

__attribute__((constructor)) static void startOfflineLyrics(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGOfflineLyrics *offline;
        offline = [SGOfflineLyrics new];
        SGAddPlayerStateObserver(offline);
    });
}
