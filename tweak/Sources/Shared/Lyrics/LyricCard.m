// Lyric cards: a few lines of the song playing, picked from a list, drawn as an image over the cover blurred
// and shared through the share sheet, the way the Music app shares lyrics. A line in another script can
// carry its pronunciation under it (the source's, else Romanise.m's, Tamil through TamilReading.m).
//
// The list is the playing track's lines as the lyrics engine keeps them (SGKaraokeLinesForTrack), so it
// works for whichever source they came from. The cover is the one Spotify gives the system's now playing,
// which either look has. Opened from the redesigned player's ⋯ menu and its full-screen lyrics.
#import <MediaPlayer/MediaPlayer.h>
#import <CoreImage/CoreImage.h>
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "Lyrics.h"

static const NSUInteger kMaxLines = 6;
static const CGSize kCardSize = {1080, 1350};

#pragma mark - the image

static UIImage *nowPlayingCover(void) {
    MPMediaItemArtwork *artwork = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyArtwork];
    return [artwork isKindOfClass:MPMediaItemArtwork.class] ? [artwork imageWithSize:CGSizeMake(600, 600)] : nil;
}

static UIImage *blurred(UIImage *image) {
    if (!image.CGImage) return nil;
    CIImage *input = [CIImage imageWithCGImage:image.CGImage];
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:[input imageByClampingToExtent] forKey:kCIInputImageKey];
    [blur setValue:@(image.size.width / 12) forKey:kCIInputRadiusKey];
    CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
    CGImageRef cg = output ? [[CIContext contextWithOptions:nil] createCGImage:output fromRect:input.extent] : NULL;
    if (!cg) return nil;
    UIImage *result = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return result;
}

static NSAttributedString *linesText(NSArray<NSArray<NSString *> *> *pairs, CGFloat size) {
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineSpacing = size * 0.12;
    style.paragraphSpacing = size * 0.45;
    NSMutableParagraphStyle *under = [style mutableCopy];
    under.paragraphSpacingBefore = -size * 0.3;
    for (NSArray<NSString *> *pair in pairs) {
        if (text.length) [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:pair[0] attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:size weight:UIFontWeightHeavy],
            NSForegroundColorAttributeName: UIColor.whiteColor, NSParagraphStyleAttributeName: style}]];
        if (pair.count > 1) {
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:pair[1]] attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:size * 0.62 weight:UIFontWeightSemibold],
                NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.72], NSParagraphStyleAttributeName: under}]];
        }
    }
    return text;
}

// `pairs`: each line, and its pronunciation after it where it shows one.
static UIImage *cardImage(NSArray<NSArray<NSString *> *> *pairs, NSString *title, NSString *artist, UIImage *cover) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:kCardSize format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect bounds = {CGPointZero, kCardSize};
        [UIColor.blackColor setFill];
        UIRectFill(bounds);
        UIImage *back = blurred(cover);
        if (back) {
            // The blurred cover filling the card, darkened so white reads over any of them.
            CGFloat side = MAX(kCardSize.width, kCardSize.height) * 1.15;
            [back drawInRect:CGRectMake((kCardSize.width - side) / 2, (kCardSize.height - side) / 2, side, side)];
            [[UIColor colorWithWhite:0 alpha:0.38] setFill];
            UIRectFillUsingBlendMode(bounds, kCGBlendModeNormal);
        }
        CGFloat margin = 96;
        // The track at the top: its cover, the title and the artist beside it.
        CGFloat thumb = 132;
        CGRect thumbRect = CGRectMake(margin, margin, thumb, thumb);
        if (cover) {
            UIBezierPath *round = [UIBezierPath bezierPathWithRoundedRect:thumbRect cornerRadius:18];
            CGContextSaveGState(context.CGContext);
            [round addClip];
            [cover drawInRect:thumbRect];
            CGContextRestoreGState(context.CGContext);
        }
        CGFloat textLeft = cover ? CGRectGetMaxX(thumbRect) + 32 : margin;
        CGFloat textWidth = kCardSize.width - margin - textLeft;
        NSMutableParagraphStyle *clip = [NSMutableParagraphStyle new];
        clip.lineBreakMode = NSLineBreakByTruncatingTail;
        [(title ?: @"") drawInRect:CGRectMake(textLeft, margin + 22, textWidth, 52) withAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:42 weight:UIFontWeightBold], NSForegroundColorAttributeName: UIColor.whiteColor,
            NSParagraphStyleAttributeName: clip}];
        [(artist ?: @"") drawInRect:CGRectMake(textLeft, margin + 74, textWidth, 46) withAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.7], NSParagraphStyleAttributeName: clip}];

        // The lines below, as large as the room lets them be, centered in it.
        CGFloat top = CGRectGetMaxY(thumbRect) + 72, bottom = kCardSize.height - margin;
        CGSize room = CGSizeMake(kCardSize.width - 2 * margin, bottom - top);
        NSAttributedString *text = nil;
        CGRect used = CGRectZero;
        for (CGFloat size = 76; size >= 30; size -= 4) {
            text = linesText(pairs, size);
            used = [text boundingRectWithSize:CGSizeMake(room.width, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin context:nil];
            if (used.size.height <= room.height) break;
        }
        CGFloat y = top + MAX(0, (room.height - used.size.height) / 2);
        [text drawWithRect:CGRectMake(margin, y, room.width, room.height) options:NSStringDrawingUsesLineFragmentOrigin context:nil];
    }];
}

#pragma mark - picking the lines

@interface SGLyricCardPicker : UITableViewController
@end

@implementation SGLyricCardPicker {
    NSArray<NSString *> *_lines, *_spoken;   // _spoken[i] is @"" where the line reads the same in Latin
    NSMutableIndexSet *_picked;
    BOOL _withSpoken, _hasSpoken;
    UIBarButtonItem *_share;
}

- (instancetype)initWithLines:(NSArray<SGKaraokeLine *> *)lines {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    BOOL japanese = SGLyricsLooksJapanese(lines);
    NSMutableArray *texts = [NSMutableArray array], *spoken = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        NSString *text = [SGKaraokeLineText(line) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!text.length || [text isEqualToString:@"♪"]) continue;
        // Two lines alike in a row (a chorus line sung twice) are one row.
        if ([texts.lastObject isEqualToString:text]) continue;
        NSString *reading = line.pronunciation ? SGKaraokeLineText(line.pronunciation) : SGLyricsRomanised(text, japanese);
        [texts addObject:text];
        [spoken addObject:reading.length ? reading : @""];
        if (reading.length) _hasSpoken = YES;
    }
    _lines = texts;
    _spoken = spoken;
    _picked = [NSMutableIndexSet indexSet];
    _withSpoken = _hasSpoken;
    self.title = @"Share Lyrics";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self action:@selector(cancel)];
    _share = [[UIBarButtonItem alloc] initWithTitle:@"Share" style:UIBarButtonItemStyleDone target:self action:@selector(share)];
    _share.enabled = NO;
    self.navigationItem.rightBarButtonItem = _share;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"line"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _hasSpoken ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self isOptions:section] ? 1 : (NSInteger)_lines.count;
}

- (BOOL)isOptions:(NSInteger)section {
    return _hasSpoken && section == 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self isOptions:section]) return nil;
    return [NSString stringWithFormat:@"Pick up to %lu lines.", (unsigned long)kMaxLines];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"line" forIndexPath:indexPath];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    if ([self isOptions:indexPath.section]) {
        content.text = @"Show Pronunciation";
        UISwitch *toggle = [UISwitch new];
        toggle.on = _withSpoken;
        [toggle addTarget:self action:@selector(spokenToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSUInteger row = (NSUInteger)indexPath.row;
        content.text = _lines[row];
        content.secondaryText = _withSpoken && _spoken[row].length ? _spoken[row] : nil;
        content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
        cell.accessoryView = nil;
        cell.accessoryType = [_picked containsIndex:row] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isOptions:indexPath.section]) return;
    NSUInteger row = (NSUInteger)indexPath.row;
    if ([_picked containsIndex:row]) [_picked removeIndex:row];
    else if (_picked.count < kMaxLines) [_picked addIndex:row];
    else return;
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    _share.enabled = _picked.count > 0;
}

- (void)spokenToggled:(UISwitch *)toggle {
    _withSpoken = toggle.on;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)share {
    NSMutableArray<NSArray<NSString *> *> *pairs = [NSMutableArray array];
    [_picked enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        NSString *spoken = self->_spoken[row];
        [pairs addObject:self->_withSpoken && spoken.length ? @[self->_lines[row], spoken] : @[self->_lines[row]]];
    }];
    SPTPlayerState *state = SGPlayerState();
    UIImage *card = cardImage(pairs, state.track.trackTitle, state.track.artistName, nowPlayingCover());
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[card] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem = _share;
    __weak SGLyricCardPicker *weakSelf = self;
    sheet.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        if (completed) [weakSelf dismissViewControllerAnimated:YES completion:nil];
    };
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

BOOL SGLyricCardAvailable(void) {
    NSString *track = SGKaraokePlayingTrack();
    return track && SGKaraokeLinesForTrack(track).count > 0;
}

void SGLyricCardPresent(UIViewController *from) {
    NSString *track = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = track ? SGKaraokeLinesForTrack(track) : nil;
    if (!lines.count) return;
    UIViewController *host = from ?: SGTopController();
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[SGLyricCardPicker alloc] initWithLines:lines]];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    SGPresentDark(navigation);
    [host presentViewController:navigation animated:YES completion:nil];
}
