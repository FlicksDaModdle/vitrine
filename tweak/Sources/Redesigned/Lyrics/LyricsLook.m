// The lyrics' look as stored, its presets and the preview's lines. The page is LyricsLookSettings.m.
#import "LyricsLook.h"

NSNotificationName const SGRLyricsLookDidChangeNotification = @"spotifyglass.redesign.lyricsLookDidChange";

// The sliders' ranges, which a stored look is held to as well.
static const SGRLyricsLook kLeast = {22, 12, 0, 0, 0}, kMost = {40, 40, 2, 2, 2};

static SGRLyricsLook presets[] = {
    {30, 24, 1, 1, 1},          // Apple Music: its 30 pt lines, 24 pt apart
    {36, 28, 1, 1, 1},          // Large
    {25, 16, 1, 1, 1},          // Compact
    {30, 24, 0, 0, 0},          // Calm: every line sharp, and nothing held glows or waves
    {32, 26, 1.4, 1.6, 1.8},    // Vivid
};

NSArray<NSString *> *SGRLyricsLookPresetNames(void) {
    return @[@"Apple Music", @"Large", @"Compact", @"Calm", @"Vivid"];
}

SGRLyricsLook SGRLyricsLookPreset(NSUInteger index) {
    return presets[MIN(index, sizeof(presets) / sizeof(*presets) - 1)];
}

static CGFloat held(CGFloat value, CGFloat least, CGFloat most) {
    return isfinite(value) ? MAX(least, MIN(most, value)) : least;
}

static CGFloat stored(NSDictionary *look, NSString *name, CGFloat fallback, CGFloat least, CGFloat most) {
    id value = look[name];
    return [value isKindOfClass:NSNumber.class] ? held([value doubleValue], least, most) : fallback;
}

SGRLyricsLook SGRLyricsLookNow(void) {
    SGRLyricsLook look = presets[0];
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGRKeyLyricsLook];
    if (!saved) return look;
    look.size = stored(saved, @"size", look.size, kLeast.size, kMost.size);
    look.spacing = stored(saved, @"spacing", look.spacing, kLeast.spacing, kMost.spacing);
    look.blur = stored(saved, @"blur", look.blur, kLeast.blur, kMost.blur);
    look.glow = stored(saved, @"glow", look.glow, kLeast.glow, kMost.glow);
    look.wave = stored(saved, @"wave", look.wave, kLeast.wave, kMost.wave);
    return look;
}

void SGRSetLyricsLook(SGRLyricsLook look, id changer) {
    [NSUserDefaults.standardUserDefaults setObject:@{
        @"size": @(held(look.size, kLeast.size, kMost.size)),
        @"spacing": @(held(look.spacing, kLeast.spacing, kMost.spacing)),
        @"blur": @(held(look.blur, kLeast.blur, kMost.blur)),
        @"glow": @(held(look.glow, kLeast.glow, kMost.glow)),
        @"wave": @(held(look.wave, kLeast.wave, kMost.wave)),
    } forKey:SGRKeyLyricsLook];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

// Equal to the slider's step, so a look slid back onto a preset's values reads as that preset again.
static BOOL same(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.01;
}

NSInteger SGRLyricsLookPresetIndex(SGRLyricsLook look) {
    for (NSUInteger i = 0; i < sizeof(presets) / sizeof(*presets); i++) {
        SGRLyricsLook preset = presets[i];
        if (same(look.size, preset.size) && same(look.spacing, preset.spacing) && same(look.blur, preset.blur)
            && same(look.glow, preset.glow) && same(look.wave, preset.wave)) return (NSInteger)i;
    }
    return -1;
}

#pragma mark - the preview's song

// Each word as [text, start, end] in ms; a line runs from its first word's start to its last word's end.
static SGKaraokeLine *sampleLine(NSArray<NSArray *> *timed) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (NSArray *piece in timed) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = piece[0];
        word.start = [piece[1] integerValue];
        word.end = [piece[2] integerValue];
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = words.firstObject.start;
    line.end = words.lastObject.end;
    line.timing = SGKaraokeTimingWords;
    return line;
}

// Words of the mod's own. The second line holds its last word for three seconds, so the glow and the wave
// show on every round.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void) {
    static NSArray<SGKaraokeLine *> *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lines = @[
            sampleLine(@[@[@"Light", @600, @1000], @[@"comes", @1000, @1400], @[@"over", @1400, @1800], @[@"the", @1800, @2000], @[@"water", @2000, @2900]]),
            sampleLine(@[@[@"hold", @3100, @3500], @[@"on", @3500, @3800], @[@"to", @3800, @4000], @[@"the", @4000, @4200], @[@"night", @4200, @7200]]),
            sampleLine(@[@[@"we", @7500, @7800], @[@"sing", @7800, @8300], @[@"it", @8300, @8500], @[@"louder", @8500, @9500]]),
            sampleLine(@[@[@"all", @9800, @10100], @[@"the", @10100, @10300], @[@"way", @10300, @10700], @[@"home", @10700, @12000]]),
        ];
    });
    return lines;
}

NSInteger SGRLyricsSampleLength(void) {
    return 13500;   // a pause after the last line, then the first again
}

#pragma mark - the size in each place

NSNotificationName const SGRLyricsSizeDidChangeNotification = @"spotifyglass.redesign.lyricsSizeDidChange";

static NSString *sizeKey(SGRLyricsPlace place) {
    switch (place) {
        case SGRLyricsPlacePreview: return @"spotifyglass.redesign.lyricsSize.preview";
        case SGRLyricsPlacePlayer: return @"spotifyglass.redesign.lyricsSize.player";
        case SGRLyricsPlaceFullScreen: return @"spotifyglass.redesign.lyricsSize.fullScreen";
        default: return nil;
    }
}

CGFloat SGRLyricsSizeFor(SGRLyricsPlace place) {
    NSString *key = sizeKey(place);
    return key ? MAX(0, [NSUserDefaults.standardUserDefaults doubleForKey:key]) : 0;
}

void SGRSetLyricsSize(SGRLyricsPlace place, CGFloat size) {
    NSString *key = sizeKey(place);
    if (!key) return;
    if (size > 0) [NSUserDefaults.standardUserDefaults setDouble:size forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsSizeDidChangeNotification object:nil];
}

UIMenu *SGRLyricsSizeMenu(SGRLyricsPlace place, NSString *title) {
    NSArray<NSArray *> *sizes = @[@[@0, @"Default"], @[@18, @"Extra Small"], @[@22, @"Small"], @[@26, @"Medium"],
                                  @[@30, @"Large"], @[@34, @"Extra Large"], @[@40, @"Huge"]];
    CGFloat current = SGRLyricsSizeFor(place);
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    for (NSArray *size in sizes) {
        CGFloat points = [size[0] doubleValue];
        UIAction *action = [UIAction actionWithTitle:size[1] image:nil identifier:nil handler:^(UIAction *a) {
            SGRSetLyricsSize(place, points);
        }];
        if (points > 0) action.subtitle = [NSString stringWithFormat:@"%.0f pt", points];
        action.state = fabs(points - current) < 0.5 ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:action];
    }
    return [UIMenu menuWithTitle:title image:[UIImage systemImageNamed:@"textformat.size"] identifier:nil options:0 children:items];
}

UIMenu *SGRLyricsSizesMenu(void) {
    return [UIMenu menuWithTitle:@"Lyrics Size" image:[UIImage systemImageNamed:@"textformat.size"] identifier:nil options:0 children:@[
        SGRLyricsSizeMenu(SGRLyricsPlacePreview, @"Under the Cover"),
        SGRLyricsSizeMenu(SGRLyricsPlacePlayer, @"In the Player"),
        SGRLyricsSizeMenu(SGRLyricsPlaceFullScreen, @"Full Screen"),
    ]];
}
