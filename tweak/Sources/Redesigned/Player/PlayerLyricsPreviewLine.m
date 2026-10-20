// Player redesign: the line under the cover drawn by the mod in place of Spotify's preview, in the lyrics view's
// own type (bold system, the Lyrics page's size, capped to the band) and lit letter by letter as it is sung: by
// the words' own times where the source timed them, and by the lyrics engine's estimate inside a line timed only
// by the line, so every synced song sweeps. It follows Romanized lyrics: the Latin letters in place of the line,
// or under it, as the lyrics view has them (SGKeyLyricsRomanisedMode).
//
// The lines and the clock are Shared/Lyrics' (the lead line at the position less the Lyrics page's delay). It is
// redrawn twenty times a second by a timer, never a display link: one capped below the screen's rate drags the
// player's 120 Hz transitions down with it. PlayerLyricsPreviewTap.x puts it over Spotify's preview, whose own
// views it leaves in place with no alpha.
#import "Core/SGCore.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Player.h"

static const CGFloat kMaxSize = 30, kMinSize = 16, kUnsungAlpha = 0.32;
static const NSTimeInterval kTick = 0.05;

@interface SGRPreviewLineLabel : UILabel
@end
@implementation SGRPreviewLineLabel
@end

@interface SGRPreviewLineView : UIView
@end

@implementation SGRPreviewLineView {
    SGRPreviewLineLabel *_label;
    NSTimer *_timer;
    SGKaraokeLine *_line;                  // the lead line shown
    NSArray<SGKaraokeWord *> *_words;      // its words as shown: the line's, or in Latin letters
    NSString *_under;                      // the romanized line under it, when the mode puts one there
    CGFloat _size;
    CGFloat _fittedWidth;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    _label = [SGRPreviewLineLabel new];
    _label.numberOfLines = 0;
    _label.isAccessibilityElement = NO;
    [self addSubview:_label];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restyle) name:SGLyricsRomanisedDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_timer invalidate];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_timer invalidate];
    _timer = nil;
    if (!self.window) return;
    __weak SGRPreviewLineView *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:kTick repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    [self tick];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = self.bounds;
    if (fabs(_fittedWidth - self.bounds.size.width) > 0.5) [self restyle];
}

- (void)restyle {
    _line = nil;   // picked and measured again at the next tick
    [self tick];
}

// The words the line shows: its own, or with Romanized in place of the original, the source's pronunciation
// where it has one, else each word in Latin letters at the original word's time.
- (void)takeLine:(SGKaraokeLine *)line {
    _line = line;
    BOOL romanised = SGFlag(SGKeyLyricsRomanised, NO);
    BOOL instead = romanised && SGInt(SGKeyLyricsRomanisedMode, 0) == 1;
    _under = nil;
    if (instead && line.pronunciation.words.count) _words = line.pronunciation.words;
    else if (instead) {
        NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
        NSString *published = SGLyricsPublishedRomanised(SGKaraokeLineText(line));
        if (published.length) {
            // A published spelling of the whole line: its words spread over the line's time.
            SGKaraokeLine *spelt = [SGKaraokeEstimatedLines(@[@(line.start), @(MAX(line.end, line.start + 1))], @[published, @""]) firstObject];
            _words = spelt.words.count ? spelt.words : line.words;
        } else {
            for (SGKaraokeWord *word in line.words) {
                NSString *latin = SGLyricsRomanised(word.text, NO);
                if (!latin.length) { [words addObject:word]; continue; }
                SGKaraokeWord *copy = [SGKaraokeWord new];
                copy.text = latin;
                copy.start = word.start;
                copy.end = word.end;
                [words addObject:copy];
            }
            _words = words;
        }
    } else {
        _words = line.words;
        if (romanised) _under = line.pronunciation ? SGKaraokeLineText(line.pronunciation) : SGLyricsRomanised(SGKaraokeLineText(line), NO);
    }
    [self fit];
}

- (NSString *)wordsText {
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in _words) {
        if (text.length && !word.joined) [text appendString:@" "];
        [text appendString:word.text ?: @""];
    }
    return text;
}

// The largest size up to the Lyrics page's (capped for the band) at which the line, and its romanization, fit.
- (void)fit {
    _fittedWidth = self.bounds.size.width;
    CGFloat height = self.bounds.size.height, width = self.bounds.size.width;
    CGFloat start = MIN(kMaxSize, MAX(kMinSize, SGRLyricsLookNow().size));
    _size = kMinSize;
    for (CGFloat size = start; size >= kMinSize; size -= 1) {
        NSAttributedString *text = [self textAt:size litUpTo:-1];
        CGRect used = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin context:nil];
        if (ceil(used.size.height) <= height || height <= 0) { _size = size; break; }
    }
}

// The line at `size`, every letter sung by `ms` lit and the rest dim; ms < 0 lights none.
- (NSAttributedString *)textAt:(CGFloat)size litUpTo:(NSInteger)ms {
    UIFont *font = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
    UIColor *lit = UIColor.whiteColor, *unlit = [UIColor colorWithWhite:1 alpha:kUnsungAlpha];
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    for (SGKaraokeWord *word in _words) {
        if (text.length && !word.joined) [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{NSFontAttributeName: font}]];
        NSString *letters = word.text ?: @"";
        double share = 0;
        if (ms >= 0) {
            NSInteger end = MAX(word.end, word.start + 1);
            share = ms <= word.start ? 0 : ms >= end ? 1 : (double)(ms - word.start) / (end - word.start);
        }
        NSUInteger litCount = (NSUInteger)round(share * letters.length);
        // Whole letters: a sung part never splits a letter (its marks, a Tamil or Devanagari cluster).
        NSRange keep = litCount < letters.length ? [letters rangeOfComposedCharacterSequenceAtIndex:litCount] : NSMakeRange(letters.length, 0);
        NSUInteger cut = litCount == 0 ? 0 : litCount >= letters.length ? letters.length : keep.location;
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[letters substringToIndex:cut]
                                                                     attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: lit}]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[letters substringFromIndex:cut]
                                                                     attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: unlit}]];
    }
    if (_under.length) {
        BOOL sung = ms >= 0 && ms >= _line.start;
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:_under] attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:round(size * 0.67) weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:sung ? 0.7 : kUnsungAlpha]}]];
    }
    return text;
}

- (void)tick {
    NSString *track = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = track ? SGKaraokeLinesForTrack(track) : nil;
    if (!lines.count) {
        _label.attributedText = nil;
        _line = nil;
        return;
    }
    NSInteger position = SGKaraokePositionMs();
    NSInteger ms = position < 0 ? -1 : position - SGKaraokeDelayMs();
    NSInteger lead = ms < 0 ? -1 : SGKaraokeLeadLine(lines, ms);
    // Between lines and before the first: the next one to come, unlit.
    SGKaraokeLine *line = lines[lead >= 0 ? (NSUInteger)lead : 0];
    if (lead >= 0 && [SGKaraokeLineText(line) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0
        && (NSUInteger)lead + 1 < lines.count) line = lines[(NSUInteger)lead + 1];
    if (line != _line) [self takeLine:line];
    _label.attributedText = [self textAt:_size litUpTo:ms];
}

@end

UIView *SGRPreviewLineMake(void) {
    return [SGRPreviewLineView new];
}

BOOL SGRPreviewLineIsOurs(UIView *view) {
    return [view isKindOfClass:SGRPreviewLineView.class] || [view isKindOfClass:SGRPreviewLineLabel.class];
}
