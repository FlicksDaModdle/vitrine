// Tamil in the Latin letters its listeners write it in ("kaadhal", "vandhaan", "konjam", "kaatru",
// "endru"), not ICU's ISO 15919 ("kātal", "vantāṉ"), which Romanise.m's Any-Latin gives and Latin-ASCII
// then flattens to "katal". Long vowels are doubled, ழ is "zh", and a stop takes its spoken sound from
// where it stands: voiced between vowels and after a nasal (க g, ச s, ட d, த dh, ப b), plain at the
// start of a word and when doubled, with the clusters spelled the usual way (ஞ்ச nj, ங்க ng, ந்த ndh,
// ன்ற ndr, ற்ற tr, ச்ச ch, த்த th). Anything that is not Tamil passes through untouched.
//
// Plain C over UTF-16 so it builds and is tested off the phone: clang -x c -DSG_TAMIL_TEST this file.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum { TAM_OTHER, TAM_VOWEL, TAM_CONS };

typedef struct {
    int kind;
    uint16_t cons;        // TAM_CONS: the consonant
    const char *vowel;    // TAM_CONS: its vowel, NULL when it has none (்); TAM_VOWEL: the vowel
    uint16_t other;       // TAM_OTHER: the character as it was
} tam_unit;

// க ங ச ஜ ஞ ட ண த ந ன ப ம ய ர ற ல ள ழ வ ஶ ஷ ஸ ஹ
static int tam_isCons(uint16_t c) {
    switch (c) {
        case 0x0B95: case 0x0B99: case 0x0B9A: case 0x0B9C: case 0x0B9E: case 0x0B9F: case 0x0BA3: case 0x0BA4:
        case 0x0BA8: case 0x0BA9: case 0x0BAA: case 0x0BAE: case 0x0BAF: case 0x0BB0: case 0x0BB1: case 0x0BB2:
        case 0x0BB3: case 0x0BB4: case 0x0BB5: case 0x0BB6: case 0x0BB7: case 0x0BB8: case 0x0BB9:
            return 1;
    }
    return 0;
}

static const char *tam_independent(uint16_t c) {
    switch (c) {
        case 0x0B85: return "a";  case 0x0B86: return "aa"; case 0x0B87: return "i";  case 0x0B88: return "ee";
        case 0x0B89: return "u";  case 0x0B8A: return "oo"; case 0x0B8E: return "e";  case 0x0B8F: return "e";
        case 0x0B90: return "ai"; case 0x0B92: return "o";  case 0x0B93: return "o";  case 0x0B94: return "au";
    }
    return NULL;
}

static const char *tam_sign(uint16_t c) {
    switch (c) {
        case 0x0BBE: return "aa"; case 0x0BBF: return "i";  case 0x0BC0: return "ee"; case 0x0BC1: return "u";
        case 0x0BC2: return "oo"; case 0x0BC6: return "e";  case 0x0BC7: return "e";  case 0x0BC8: return "ai";
        case 0x0BCA: return "o";  case 0x0BCB: return "o";  case 0x0BCC: return "au";
    }
    return NULL;
}

static int tam_isNasal(uint16_t c) { return c == 0x0B99 || c == 0x0B9E || c == 0x0BA3 || c == 0x0BA8 || c == 0x0BAE || c == 0x0BA9; }
static int tam_isLiquid(uint16_t c) { return c == 0x0BAF || c == 0x0BB0 || c == 0x0BB2 || c == 0x0BB5 || c == 0x0BB4 || c == 0x0BB3; }

// The text as units: a consonant with its vowel, a vowel on its own, or anything else.
static size_t tam_parse(const uint16_t *in, size_t n, tam_unit *units) {
    size_t count = 0;
    for (size_t i = 0; i < n; i++) {
        uint16_t c = in[i];
        tam_unit u = {TAM_OTHER, 0, NULL, c};
        if (tam_isCons(c)) {
            u.kind = TAM_CONS;
            u.cons = c;
            u.vowel = "a";
            if (i + 1 < n) {
                uint16_t s = in[i + 1];
                if (s == 0x0BCD) { u.vowel = NULL; i++; }
                else if (tam_sign(s)) {
                    u.vowel = tam_sign(s);
                    i++;
                    // ொ ோ ௌ written as two marks: ெ or ே, then ா or ௗ.
                    if ((s == 0x0BC6 || s == 0x0BC7) && i + 1 < n && in[i + 1] == 0x0BBE) { u.vowel = "o"; i++; }
                    else if (s == 0x0BC6 && i + 1 < n && in[i + 1] == 0x0BD7) { u.vowel = "au"; i++; }
                }
            }
        } else if (tam_independent(c)) {
            u.kind = TAM_VOWEL;
            u.vowel = tam_independent(c);
        }
        units[count++] = u;
    }
    return count;
}

// The consonant's letters where it stands. prev and next are the units around it, NULL at the ends.
static const char *tam_consonant(const tam_unit *prev, const tam_unit *u, const tam_unit *next) {
    uint16_t c = u->cons;
    int dead = u->vowel == NULL;
    uint16_t nextCons = next && next->kind == TAM_CONS ? next->cons : 0;
    uint16_t prevDead = prev && prev->kind == TAM_CONS && prev->vowel == NULL ? prev->cons : 0;
    int start = !prev || prev->kind == TAM_OTHER;
    int afterVowel = prev && (prev->kind == TAM_VOWEL || (prev->kind == TAM_CONS && prev->vowel));
    int voiced = afterVowel || (prevDead && (tam_isNasal(prevDead) || tam_isLiquid(prevDead)));
    // Either half of a doubled stop is hard: க்க kk, ட்ட tt, ப்ப pp.
    int geminate = prevDead == c || (dead && nextCons == c);

    // A dead letter that the next one spells for both.
    if (dead && nextCons == c && (c == 0x0BA4 || c == 0x0B9A)) return "";   // த்த th, ச்ச ch
    if (dead && c == 0x0BB1) return nextCons == 0x0BB1 ? "t" : "r";          // ற்ற tr, ற்க rk
    if (dead && c == 0x0B99 && nextCons == 0x0B95) return "n";               // ங்க ng
    if (dead && c == 0x0B9E && nextCons == 0x0B9A) return "n";               // ஞ்ச nj

    switch (c) {
        case 0x0B95:   // க
            if (geminate || start) return "k";
            return voiced ? "g" : "k";
        case 0x0B9A:   // ச
            if (geminate) return "ch";
            if (prevDead == 0x0B9E) return "j";
            if (prevDead == 0x0B9F || prevDead == 0x0BB1) return "ch";
            if (start || voiced) return "s";
            return "ch";
        case 0x0B9F:   // ட
            if (geminate || start) return "t";
            return voiced ? "d" : "t";
        case 0x0BA4:   // த
            if (geminate || start) return "th";
            return voiced ? "dh" : "th";
        case 0x0BAA:   // ப
            if (geminate || start) return "p";
            return voiced ? "b" : "p";
        case 0x0BB1:   // ற
            if (prevDead == 0x0BA9) return "dr";   // ன்ற ndr
            return "r";
        case 0x0B99: return "ng";
        case 0x0B9E: return "nj";
        case 0x0BA3: case 0x0BA8: case 0x0BA9: return "n";
        case 0x0BAE: return "m";
        case 0x0BAF: return "y";
        case 0x0BB0: return "r";
        case 0x0BB2: case 0x0BB3: return "l";
        case 0x0BB5: return "v";
        case 0x0BB4: return "zh";
        case 0x0B9C: return "j";
        case 0x0BB7: case 0x0BB6: return "sh";
        case 0x0BB8: return "s";
        case 0x0BB9: return "h";
    }
    return "";
}

static size_t tam_put(char *out, size_t at, size_t cap, const char *s) {
    size_t len = strlen(s);
    if (at + len < cap) memcpy(out + at, s, len);
    return at + len;
}

// UTF-8 of one UTF-16 unit that is not Tamil (the BMP is all a lyric line needs; surrogates pass as they are).
static size_t tam_putOther(char *out, size_t at, size_t cap, uint16_t c) {
    char b[4];
    size_t len;
    if (c < 0x80) { b[0] = (char)c; len = 1; }
    else if (c < 0x800) { b[0] = (char)(0xC0 | (c >> 6)); b[1] = (char)(0x80 | (c & 0x3F)); len = 2; }
    else { b[0] = (char)(0xE0 | (c >> 12)); b[1] = (char)(0x80 | ((c >> 6) & 0x3F)); b[2] = (char)(0x80 | (c & 0x3F)); len = 3; }
    if (at + len < cap) memcpy(out + at, b, len);
    return at + len;
}

// Writes the reading as NUL-terminated UTF-8 into out and returns its length, which is more than
// cap - 1 when out was too small. Non-Tamil text comes out as it went in.
static size_t SGTamilRead(const uint16_t *in, size_t n, char *out, size_t cap, tam_unit *scratch) {
    size_t count = tam_parse(in, n, scratch), at = 0;
    for (size_t i = 0; i < count; i++) {
        const tam_unit *u = &scratch[i];
        const tam_unit *prev = i ? &scratch[i - 1] : NULL, *next = i + 1 < count ? &scratch[i + 1] : NULL;
        if (u->kind == TAM_CONS) {
            at = tam_put(out, at, cap, tam_consonant(prev, u, next));
            if (u->vowel) at = tam_put(out, at, cap, u->vowel);
        } else if (u->kind == TAM_VOWEL) {
            at = tam_put(out, at, cap, u->vowel);
        } else if (u->other == 0x0B83) {   // ஃ: ஃப is f, else h
            if (next && next->kind == TAM_CONS && next->cons == 0x0BAA) { at = tam_put(out, at, cap, "f"); if (next->vowel) at = tam_put(out, at, cap, next->vowel); i++; }
            else at = tam_put(out, at, cap, "h");
        } else if (u->other >= 0x0BE6 && u->other <= 0x0BEF) {
            at = tam_putOther(out, at, cap, (uint16_t)('0' + u->other - 0x0BE6));
        } else if (u->other >= 0x0B80 && u->other <= 0x0BFF) {
            // Another Tamil sign on its own (a stray mark): left out.
        } else {
            at = tam_putOther(out, at, cap, u->other);
        }
    }
    if (cap) out[at < cap ? at : cap - 1] = 0;
    return at;
}

#ifdef __OBJC__
#import "Lyrics.h"

NSString *SGTamilReading(NSString *text) {
    if ([text rangeOfString:@"[\\u0B80-\\u0BFF]" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    NSString *composed = text.precomposedStringWithCanonicalMapping;
    NSUInteger n = composed.length;
    uint16_t *in = malloc(n * sizeof(uint16_t));
    tam_unit *units = malloc(n * sizeof(tam_unit));
    size_t cap = n * 4 + 16;
    char *out = malloc(cap);
    [composed getCharacters:in range:NSMakeRange(0, n)];
    SGTamilRead(in, n, out, cap, units);
    NSString *reading = [NSString stringWithUTF8String:out];
    free(in);
    free(units);
    free(out);
    return reading;
}
#endif

#ifdef SG_TAMIL_TEST
#include <stdio.h>
// Reads UTF-8 lines from stdin and prints each one's reading.
int main(void) {
    char line[4096];
    while (fgets(line, sizeof line, stdin)) {
        uint16_t in[4096];
        size_t n = 0;
        for (unsigned char *p = (unsigned char *)line; *p && *p != '\n';) {
            uint32_t c;
            if (*p < 0x80) c = *p++;
            else if ((*p & 0xE0) == 0xC0) { c = (uint32_t)(*p & 0x1F) << 6 | (p[1] & 0x3F); p += 2; }
            else { c = (uint32_t)(*p & 0x0F) << 12 | (uint32_t)(p[1] & 0x3F) << 6 | (p[2] & 0x3F); p += 3; }
            in[n++] = (uint16_t)c;
        }
        tam_unit units[4096];
        char out[16384];
        SGTamilRead(in, n, out, sizeof out, units);
        puts(out);
    }
    return 0;
}
#endif
