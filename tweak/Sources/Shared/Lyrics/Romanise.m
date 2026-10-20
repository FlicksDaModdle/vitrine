// A line in the Latin alphabet, offline, by Apple's own transforms (ICU's under them). Japanese goes
// through the tokenizer's Latin transcription, which reads kanji the Japanese way: Any-Latin alone
// reads them as Mandarin (君の名前 as "jūnno míng qián" instead of "kimi no namae"). Pinyin keeps its
// tone marks; every other script is brought down to plain ASCII, which reads better sung along to
// than ICU's scholarly marks (Greek "Kalēméra", Thai "s̄wạs̄dī").
//
// ponytail: ICU transliterates rather than reads aloud: Arabic and Hebrew come out as their consonants
// ("mrhba"), Thai in ISO 11940's spelling rather than the one signs use, and a line mixing Latin with
// another script loses the Latin part's accents ("Café" as "Cafe"). A reading per language is the upgrade.
#import "Lyrics.h"

NSNotificationName const SGLyricsRomanisedDidChangeNotification = @"spotifyglass.lyricsRomanisedDidChange";

static BOOL has(NSString *text, NSString *pattern) {
    return [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

static BOOL hasKana(NSString *text) {
    return has(text, @"[\\p{Hiragana}\\p{Katakana}]");
}

BOOL SGLyricsLooksJapanese(NSArray<SGKaraokeLine *> *lines) {
    for (SGKaraokeLine *line in lines) {
        if (hasKana(SGKaraokeLineText(line))) return YES;
    }
    return NO;
}

// The tokenizer's reading of each word, a space between words; what it has no reading for (punctuation,
// another script) is kept for the transform after it.
static NSString *readJapanese(NSString *text) {
    NSMutableString *read = [NSMutableString string];
    CFLocaleRef japanese = CFLocaleCreate(NULL, CFSTR("ja"));
    CFStringTokenizerRef words = CFStringTokenizerCreate(NULL, (__bridge CFStringRef)text, CFRangeMake(0, text.length),
                                                         kCFStringTokenizerUnitWord, japanese);
    NSUInteger from = 0;
    while (CFStringTokenizerAdvanceToNextToken(words) != kCFStringTokenizerTokenNone) {
        CFRange range = CFStringTokenizerGetCurrentTokenRange(words);
        NSString *between = [text substringWithRange:NSMakeRange(from, range.location - from)];
        NSString *word = CFBridgingRelease(CFStringTokenizerCopyCurrentTokenAttribute(words, kCFStringTokenizerAttributeLatinTranscription));
        if (read.length && !between.length) [read appendString:@" "];
        [read appendString:between];
        [read appendString:word ?: [text substringWithRange:NSMakeRange(range.location, range.length)]];
        from = range.location + range.length;
    }
    [read appendString:[text substringFromIndex:from]];
    CFRelease(words);
    CFRelease(japanese);
    return read;
}

NSString *SGLyricsRomanised(NSString *text, BOOL japanese) {
    // Only a line with a letter of another script: Latin with accents (German, Vietnamese) is left alone.
    if (!text.length || !has(text, @"[\\p{L}&&[^\\p{Latin}]]")) return nil;
    // The song's own published spelling of the line, where one was found (PublishedRomanisation.m).
    NSString *published = SGLyricsPublishedRomanised(text);
    if (published.length) return published;
    static NSCache<NSString *, NSString *> *kept;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ kept = [NSCache new]; });
    NSString *key = japanese ? [@"ja:" stringByAppendingString:text] : text;
    NSString *romanised = [kept objectForKey:key];
    if (romanised) return romanised.length ? romanised : nil;
    BOOL kana = japanese || hasKana(text);
    // Tamil and the other Indian scripts read the way their listeners spell them (TamilReading.m,
    // IndicReading.m), and only what else is left goes on.
    NSString *tamil = kana ? nil : SGTamilReading(text);
    NSString *indic = kana ? nil : SGIndicReading(tamil ?: text);
    NSString *native = indic ?: tamil;
    if (native && !has(native, @"[\\p{L}&&[^\\p{Latin}]]")) {
        romanised = [native stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([romanised caseInsensitiveCompare:text] == NSOrderedSame) romanised = @"";
        [kept setObject:romanised forKey:key];
        return romanised.length ? romanised : nil;
    }
    NSString *source = kana ? readJapanese(text) : (native ?: text);
    // Han left over is Chinese: its pinyin keeps the tones, and only its punctuation is made ASCII.
    NSString *transform = !kana && has(text, @"\\p{Han}") ? @"Any-Latin; [[:P:][:Zs:]] Latin-ASCII" : @"Any-Latin; Latin-ASCII";
    romanised = [[source stringByApplyingTransform:transform reverse:NO]
                 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] ?: @"";
    if ([romanised caseInsensitiveCompare:text] == NSOrderedSame) romanised = @"";
    [kept setObject:romanised forKey:key];
    return romanised.length ? romanised : nil;
}
