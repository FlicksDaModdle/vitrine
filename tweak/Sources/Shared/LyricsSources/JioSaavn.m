// JioSaavn, for the Indian catalog the others miss: Tamil, Telugu, Malayalam, Kannada, Hindi and Punjabi
// film songs, often in their own script, which Romanise.m (and TamilReading.m for Tamil) reads in Latin
// letters under each line. Its lyrics are plain text, untimed, so it sits after every timed source and
// only fills a page that would otherwise stay empty.
//
// Two calls on its web API, no key: search.getResults by title and artist for the song's id, then
// lyrics.getLyrics with that id. Its answers carry HTML entities and <br> between lines. The shapes
// differ between its API versions (the details under more_info or at the top), so both are read.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kAPI = @"https://www.jiosaavn.com/api.php";
static const NSInteger kLengthSlack = 6;

static NSString *unescape(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSMutableString *s = [text mutableCopy];
    [s replaceOccurrencesOfString:@"<br>" withString:@"\n" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"<br/>" withString:@"\n" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"<br />" withString:@"\n" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    NSDictionary<NSString *, NSString *> *entities = @{@"&quot;": @"\"", @"&#039;": @"'", @"&#39;": @"'", @"&apos;": @"'",
                                                       @"&lt;": @"<", @"&gt;": @">", @"&nbsp;": @" ", @"&amp;": @"&"};
    for (NSString *entity in @[@"&quot;", @"&#039;", @"&#39;", @"&apos;", @"&lt;", @"&gt;", @"&nbsp;", @"&amp;"]) {
        [s replaceOccurrencesOfString:entity withString:entities[entity] options:0 range:NSMakeRange(0, s.length)];
    }
    return s;
}

static id field(NSDictionary *song, NSString *key) {
    NSDictionary *more = [song[@"more_info"] isKindOfClass:NSDictionary.class] ? song[@"more_info"] : nil;
    return more[key] ?: song[key];
}

static NSString *titleOf(NSDictionary *song) {
    id title = song[@"title"] ?: song[@"song"];
    return unescape([title isKindOfClass:NSString.class] ? title : nil) ?: @"";
}

static NSString *artistsOf(NSDictionary *song) {
    NSMutableArray *names = [NSMutableArray array];
    NSDictionary *map = [field(song, @"artistMap") isKindOfClass:NSDictionary.class] ? field(song, @"artistMap") : nil;
    for (NSDictionary *artist in [map[@"primary_artists"] isKindOfClass:NSArray.class] ? map[@"primary_artists"] : @[]) {
        if ([artist isKindOfClass:NSDictionary.class] && [artist[@"name"] isKindOfClass:NSString.class]) [names addObject:artist[@"name"]];
    }
    for (NSString *key in @[@"primary_artists", @"singers", @"music"]) {
        id value = field(song, key);
        if ([value isKindOfClass:NSString.class]) [names addObject:value];
    }
    id subtitle = song[@"subtitle"];
    if ([subtitle isKindOfClass:NSString.class]) [names addObject:subtitle];
    return unescape([names componentsJoinedByString:@" "]) ?: @"";
}

static BOOL hasLyrics(NSDictionary *song) {
    id value = field(song, @"has_lyrics");
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

// How close a result is to the track: its title has the track's (or the other way round), one of the
// track's artists is named in it, and its length agrees. -1 for one that is not the track.
static NSInteger scoreOf(NSDictionary *song, SGLyricsQuery *query) {
    if (![song isKindOfClass:NSDictionary.class] || !hasLyrics(song)) return -1;
    NSString *title = SGLyricsBareText(titleOf(song)), *wanted = SGLyricsBareText(query.title);
    // The film is in brackets on JioSaavn ("Song (From "Film")") and often not on Spotify.
    NSString *wantedShort = SGLyricsBareText([query.title componentsSeparatedByString:@"("].firstObject);
    if (!title.length || !wantedShort.length) return -1;
    BOOL titled = [title containsString:wantedShort] || [wanted containsString:title];
    if (!titled) return -1;
    NSInteger score = [title isEqualToString:wanted] ? 3 : 1;
    NSString *artists = SGLyricsBareText(artistsOf(song));
    for (NSString *artist in [query.artist componentsSeparatedByString:@","]) {
        NSString *bare = SGLyricsBareText(artist);
        if (bare.length && [artists containsString:bare]) { score += 2; break; }
    }
    NSInteger length = [field(song, @"duration") integerValue];
    if (query.seconds > 0 && length > 0) {
        if (labs(length - query.seconds) > kLengthSlack) return -1;
        score += 2;
    }
    return score;
}

static NSArray *resultsIn(id root) {
    if (![root isKindOfClass:NSDictionary.class]) return @[];
    for (id list in @[root[@"results"] ?: @[], [root[@"songs"] isKindOfClass:NSDictionary.class] ? root[@"songs"][@"data"] ?: @[] : @[]]) {
        if ([list isKindOfClass:NSArray.class] && [list count]) return list;
    }
    return @[];
}

static SGLyricsResult *resultFrom(id root) {
    NSString *text = [root isKindOfClass:NSDictionary.class] ? unescape(root[@"lyrics"]) : nil;
    if (!text.length) return nil;
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSString *row in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [row stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        // Runs of empty rows are one break.
        if (!line.length && (!texts.count || [texts.lastObject isEqualToString:@"♪"])) continue;
        [starts addObject:@0];
        [texts addObject:line.length ? line : @"♪"];
    }
    while ([texts.lastObject isEqualToString:@"♪"]) { [texts removeLastObject]; [starts removeLastObject]; }
    if (!texts.count) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.provider = @"JioSaavn";
    result.starts = starts;
    result.texts = texts;
    result.karaokeLines = SGKaraokeStaticLines(texts);
    return result;
}

static NSDictionary<NSString *, NSString *> *common(void) {
    return @{@"_format": @"json", @"_marker": @"0", @"api_version": @"4", @"ctx": @"web6dot0"};
}

SGLyricsAsk SGJioSaavnAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!query.title.length) {
        done(nil);
        return;
    }
    NSString *firstArtist = [query.artist componentsSeparatedByString:@","].firstObject ?: @"";
    NSString *title = [query.title componentsSeparatedByString:@" - "].firstObject;
    NSMutableDictionary *search = [common() mutableCopy];
    [search addEntriesFromDictionary:@{@"__call": @"search.getResults", @"n": @"10", @"p": @"1",
                                       @"q": [NSString stringWithFormat:@"%@ %@", title, firstArtist]}];
    SGLyricsGetJSON(SGLyricsURL(kAPI, search), nil, ^(id root) {
        NSDictionary *best = nil;
        NSInteger bestScore = -1;
        for (NSDictionary *song in resultsIn(root)) {
            NSInteger score = scoreOf(song, query);
            if (score > bestScore) { best = song; bestScore = score; }
        }
        NSString *songID = [best[@"id"] isKindOfClass:NSString.class] ? best[@"id"] : nil;
        id lyricsID = field(best, @"lyrics_id");
        NSString *ask = [lyricsID isKindOfClass:NSString.class] && [lyricsID length] ? lyricsID : songID;
        if (!ask) {
            SGLog(@"jiosaavn: no song with lyrics for %@ by %@", query.title, query.artist);
            done(nil);
            return;
        }
        NSMutableDictionary *lyrics = [common() mutableCopy];
        [lyrics addEntriesFromDictionary:@{@"__call": @"lyrics.getLyrics", @"lyrics_id": ask}];
        SGLyricsGetJSON(SGLyricsURL(kAPI, lyrics), nil, ^(id answer) {
            SGLyricsResult *result = resultFrom(answer);
            SGLog(@"jiosaavn: %@ by %@ (%@) gave %@", query.title, query.artist, ask,
                  result ? [NSString stringWithFormat:@"%lu untimed lines", (unsigned long)result.texts.count] : @"nothing");
            done(result);
        });
    });
};
