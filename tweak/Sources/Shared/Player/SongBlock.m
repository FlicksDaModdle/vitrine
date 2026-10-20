// Blocked songs: a song blocked from the player's ⋯ menu is skipped whenever the player moves onto it, from a
// playlist, an album, the queue, autoplay or a radio, the way Blocked artists skips an artist (ArtistBlock/). The
// list keeps each song's title and artist for the Blocked songs page, where a swipe unblocks one.
//
// A run of blocked songs is skipped through, but no more than kMaxSkips in kSkipWindow, so a context of nothing
// but blocked songs does not spin. Applies at once.
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "PlayerSettings.h"
#import "PlayerState.h"

static NSString *const kKey = @"spotifyglass.blockedSongs";   // uri -> @[title, artist]
static const NSUInteger kMaxSkips = 5;
static const NSTimeInterval kSkipWindow = 10;

NSDictionary<NSString *, NSArray<NSString *> *> *SGBlockedSongs(void) {
    id stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kKey];
    return [stored isKindOfClass:NSDictionary.class] ? stored : @{};
}

BOOL SGSongBlocked(NSString *uri) {
    return uri.length && SGBlockedSongs()[uri] != nil;
}

void SGSetSongBlocked(NSString *uri, NSString *title, NSString *artist, BOOL blocked) {
    if (!uri.length) return;
    NSMutableDictionary *songs = [SGBlockedSongs() mutableCopy];
    if (blocked) songs[uri] = @[title ?: @"", artist ?: @""];
    else [songs removeObjectForKey:uri];
    [NSUserDefaults.standardUserDefaults setObject:songs forKey:kKey];
    SGLog(@"song block: %@ %@", blocked ? @"blocked" : @"unblocked", uri);
}

static void skipNext(void) {
    id player = SGKaraokePlayer();
    if ([player respondsToSelector:@selector(skipToNextTrackWithOptions:)]) [(id<SPTPlayer>)player skipToNextTrackWithOptions:nil];
}

void SGBlockPlayingSong(BOOL blocked) {
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *uri = SGURIString(track.URI);
    if (!uri) return;
    SGSetSongBlocked(uri, track.trackTitle, track.artistName, blocked);
    if (blocked) skipNext();
}

@interface SGSongSkipper : NSObject <SGPlayerStateObserver>
@end

@implementation SGSongSkipper {
    NSString *_seen;
    NSMutableArray<NSDate *> *_skips;
}
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    if (!uri || [uri isEqualToString:_seen]) return;
    _seen = uri;
    if (!SGSongBlocked(uri)) return;
    if (!_skips) _skips = [NSMutableArray array];
    NSDate *now = NSDate.date;
    [_skips filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *at, NSDictionary *bindings) {
        return [now timeIntervalSinceDate:at] < kSkipWindow;
    }]];
    if (_skips.count >= kMaxSkips) {
        SGLog(@"song block: %@ is blocked, but %lu were skipped just now; left to play", uri, (unsigned long)_skips.count);
        return;
    }
    [_skips addObject:now];
    SGLog(@"song block: skipped %@", state.track.trackTitle ?: uri);
    skipNext();
}
@end

__attribute__((constructor)) static void startSongBlock(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGSongSkipper *skipper;
        skipper = [SGSongSkipper new];
        SGAddPlayerStateObserver(skipper);
    });
}

#pragma mark - the page

@interface SGSongBlockPage : SGPage
@end

@implementation SGSongBlockPage {
    NSArray<NSString *> *_uris;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Blocked Songs";
    [self reload];
    return self;
}

- (void)reload {
    NSDictionary<NSString *, NSArray<NSString *> *> *songs = SGBlockedSongs();
    _uris = [songs.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [songs[a].firstObject localizedCaseInsensitiveCompare:songs[b].firstObject];
    }];
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)_uris.count, 1);
}

- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return @"Block the song playing from the player's ⋯ menu. Blocked songs are skipped wherever they come up. Swipe one to unblock it.";
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    if (!_uris.count) {
        content.text = @"No blocked songs";
        content.textProperties.color = UIColor.secondaryLabelColor;
    } else {
        NSArray<NSString *> *song = SGBlockedSongs()[_uris[(NSUInteger)path.row]];
        content.text = song.firstObject.length ? song.firstObject : _uris[(NSUInteger)path.row];
        content.secondaryText = song.count > 1 ? song[1] : nil;
        content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    }
    cell.contentConfiguration = content;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (!_uris.count) return nil;
    NSString *uri = _uris[(NSUInteger)path.row];
    UIContextualAction *unblock = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Unblock"
                                                                        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        SGSetSongBlocked(uri, nil, nil, NO);
        [self reload];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[unblock]];
}

@end

UIViewController *SGSongBlockSettingsPage(void) {
    return [SGSongBlockPage new];
}
