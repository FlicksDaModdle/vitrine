// The romanized lyrics a song already has published, over Romanise.m's own reading. Indian film and indie songs
// are nearly always put out in Latin letters too, by the label or the people who sync them ("Tanglish"), and
// those spellings are the ones listeners know: "kaadhal" or "kadhal", "nenjukulle", names as the credits spell
// them. So when a song's lines are mostly in an Indian script, the same song is looked up again for a copy in
// Latin letters: LRCLIB's records (synced ones first) and JioSaavn's lyrics. A copy that lines up with the song's
// lines (by their times when both are synced, else line for line when the two have as many lines) becomes each
// line's pronunciation, which every reader of a romanized line takes before the transform's (SGLyricsRomanised
// asks SGLyricsPublishedRomanised first, the lyrics view takes the line's pronunciation).
//
// Only while Romanized lyrics is on, once per track, and nothing changes when no copy lines up.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "LyricsSources.h"

static NSString *const kLrcLibSearch = @"https://lrclib.net/api/search";
static const NSInteger kStartSlackMs = 900, kLengthSlack = 5;
static const double kLinedUpShare = 0.6;

static NSMutableSet<NSString *> *sg_looked;
static NSMutableDictionary<NSString *, NSString *> *sg_published;   // a line's text -> its published spelling

static BOOL indic(unichar c) { return c >= 0x0900 && c <= 0x0D7F; }

// The share of a text's letters that are in an Indian script, and of them that are Latin.
static void shares(NSString *text, double *indicShare, double *latinShare) {
    NSUInteger letters = 0, ind = 0, latin = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (indic(c)) { ind++; letters++; }
        else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) { latin++; letters++; }
        else if ([NSCharacterSet.letterCharacterSet characterIsMember:c]) letters++;
    }
    if (indicShare) *indicShare = letters ? (double)ind / letters : 0;
    if (latinShare) *latinShare = letters ? (double)latin / letters : 0;
}

static NSString *trimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL isBreak(NSString *text) {
    return !text.length || [text isEqualToString:@"♪"];
}

NSString *SGLyricsPublishedRomanised(NSString *text) {
    if (!text.length) return nil;
    @synchronized (sg_published) { return sg_published[trimmed(text)]; }
}

// LRC's lines with their starts, the tags and empty rows left out.
static NSArray<NSArray *> *timedRows(NSString *lrc) {
    static NSRegularExpression *stamp;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stamp = [NSRegularExpression regularExpressionWithPattern:@"^\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]" options:0 error:nil];
    });
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *row in [lrc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSTextCheckingResult *match = [stamp firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!match) continue;
        NSInteger ms = ([row substringWithRange:[match rangeAtIndex:1]].integerValue * 60
                        + [row substringWithRange:[match rangeAtIndex:2]].integerValue) * 1000;
        NSRange part = [match rangeAtIndex:3];
        if (part.location != NSNotFound) {
            NSString *digits = [row substringWithRange:part];
            ms += digits.integerValue * (digits.length == 1 ? 100 : digits.length == 2 ? 10 : 1);
        }
        NSString *text = trimmed([row substringFromIndex:NSMaxRange(match.range)]);
        if (!isBreak(text)) [rows addObject:@[@(ms), text]];
    }
    return rows;
}

static NSArray<NSString *> *plainRows(NSString *plain) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *row in [plain componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *text = trimmed(row);
        if (!isBreak(text)) [rows addObject:text];
    }
    return rows;
}

static BOOL mostlyLatin(NSArray<NSString *> *texts) {
    double latin = 0;
    shares([texts componentsJoinedByString:@" "], NULL, &latin);
    return texts.count >= 4 && latin > 0.85;
}

// Each of `lines` (those with words) given its spelling from `rows`: by start where both are timed, else by place
// when the two have the same number of lines. Nil when too few line up.
static NSDictionary<NSString *, NSString *> *lineUp(NSArray<SGKaraokeLine *> *lines, NSArray<NSArray *> *timed, NSArray<NSString *> *plain) {
    NSMutableArray<SGKaraokeLine *> *sung = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) if (!isBreak(trimmed(SGKaraokeLineText(line)))) [sung addObject:line];
    if (sung.count < 4) return nil;
    NSMutableDictionary<NSString *, NSString *> *spelt = [NSMutableDictionary dictionary];
    BOOL synced = sung.lastObject.start > 0;
    if (synced && timed.count) {
        for (SGKaraokeLine *line in sung) {
            NSArray *best = nil;
            NSInteger off = NSIntegerMax;
            for (NSArray *row in timed) {
                NSInteger d = labs([row[0] integerValue] - line.start);
                if (d < off) { off = d; best = row; }
            }
            if (best && off <= kStartSlackMs) spelt[trimmed(SGKaraokeLineText(line))] = best[1];
        }
    }
    if ((double)spelt.count / sung.count < kLinedUpShare) {
        [spelt removeAllObjects];
        NSArray<NSString *> *rows = plain;
        if (!rows.count && timed.count) {
            NSMutableArray *texts = [NSMutableArray array];
            for (NSArray *row in timed) [texts addObject:row[1]];
            rows = texts;
        }
        if (rows.count != sung.count) return nil;
        for (NSUInteger i = 0; i < sung.count; i++) spelt[trimmed(SGKaraokeLineText(sung[i]))] = rows[i];
    }
    return (double)spelt.count / sung.count >= kLinedUpShare ? spelt : nil;
}

static void adopt(NSString *track, NSArray<SGKaraokeLine *> *lines, NSDictionary<NSString *, NSString *> *spelt, NSString *from) {
    @synchronized (sg_published) { [sg_published addEntriesFromDictionary:spelt]; }
    NSMutableArray<SGKaraokeLine *> *withSpelling = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) {
        NSString *latin = spelt[trimmed(SGKaraokeLineText(line))];
        if (!latin || line.pronunciation) {
            [withSpelling addObject:line];
            continue;
        }
        SGKaraokeLine *copy = [line copy];
        copy.pronunciation = SGLyricsPronunciation(nil, latin, copy);
        [withSpelling addObject:copy];
    }
    SGLog(@"romanized: %lu lines of %@ spelled as %@ publishes them", (unsigned long)spelt.count, track, from);
    SGKaraokeKeepLines(track, withSpelling);
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
}

// LRCLIB first (its synced records line up by time), then JioSaavn's plain text.
static void lookUp(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *title, NSString *artist, NSInteger seconds) {
    NSString *firstArtist = trimmed([artist componentsSeparatedByString:@","].firstObject ?: @"");
    NSString *shortTitle = trimmed([[title componentsSeparatedByString:@" - "].firstObject componentsSeparatedByString:@"("].firstObject ?: title);
    NSURL *url = SGLyricsURL(kLrcLibSearch, @{@"track_name": shortTitle, @"artist_name": firstArtist});
    SGLyricsGetJSON(url, @{@"User-Agent": @"Vitrine " @SG_VERSION}, ^(id found) {
        NSArray *records = [found isKindOfClass:NSArray.class] ? found : @[];
        // Synced records first, then the closest in length.
        records = [records sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            BOOL sa = [a isKindOfClass:NSDictionary.class] && [a[@"syncedLyrics"] isKindOfClass:NSString.class];
            BOOL sb = [b isKindOfClass:NSDictionary.class] && [b[@"syncedLyrics"] isKindOfClass:NSString.class];
            return sa == sb ? NSOrderedSame : sa ? NSOrderedAscending : NSOrderedDescending;
        }];
        for (NSDictionary *record in records) {
            if (![record isKindOfClass:NSDictionary.class]) continue;
            NSInteger length = (NSInteger)[record[@"duration"] doubleValue];
            if (seconds > 0 && length > 0 && labs(length - seconds) > kLengthSlack) continue;
            NSString *synced = [record[@"syncedLyrics"] isKindOfClass:NSString.class] ? record[@"syncedLyrics"] : nil;
            NSString *plain = [record[@"plainLyrics"] isKindOfClass:NSString.class] ? record[@"plainLyrics"] : nil;
            NSArray<NSArray *> *timed = synced ? timedRows(synced) : @[];
            NSArray<NSString *> *rows = plain ? plainRows(plain) : @[];
            NSMutableArray<NSString *> *texts = [NSMutableArray array];
            for (NSArray *row in timed) [texts addObject:row[1]];
            if (!mostlyLatin(texts.count ? texts : rows)) continue;
            NSDictionary *spelt = lineUp(lines, timed, rows);
            if (spelt) {
                adopt(track, lines, spelt, @"LRCLIB");
                return;
            }
        }
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.trackID = track;
        query.title = title;
        query.artist = artist;
        query.seconds = seconds;
        SGJioSaavnAsk(query, ^(SGLyricsResult *result) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSString *text in result.texts) if (!isBreak(trimmed(text))) [rows addObject:trimmed(text)];
            NSDictionary *spelt = mostlyLatin(rows) ? lineUp(lines, @[], rows) : nil;
            if (spelt) adopt(track, lines, spelt, @"JioSaavn");
            else SGLog(@"romanized: no published spelling lines up for %@", track);
        });
    });
}

void SGLyricsFindPublishedRomanisation(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    if (!track.length || lines.count < 4 || !SGFlag(SGKeyLyricsRomanised, NO)) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_looked = [NSMutableSet set];
        sg_published = [NSMutableDictionary dictionary];
    });
    if ([sg_looked containsObject:track]) return;
    // Lines a source spelled out already (Apple Music's TTML) keep theirs.
    NSUInteger spelled = 0;
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        if (line.pronunciation) spelled++;
        [texts addObject:SGKaraokeLineText(line)];
    }
    if (spelled * 2 > lines.count) return;
    double share = 0;
    shares([texts componentsJoinedByString:@" "], &share, NULL);
    if (share < 0.5) return;
    SPTPlayerTrack *player = SGKaraokeTrackFor(track);
    NSString *title = player.trackTitle, *artist = player.artistName;
    if (!title.length || !artist.length) return;
    [sg_looked addObject:track];
    SPTPlayerState *state = SGPlayerState();
    NSInteger seconds = [SGURIString(state.track.URI) hasSuffix:track] ? (NSInteger)round(state.duration) : 0;
    lookUp(track, lines, title, artist, seconds);
}
