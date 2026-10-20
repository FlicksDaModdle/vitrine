// The Indian scripts besides Tamil (TamilReading.m) in the Latin letters their listeners write them in:
// Hindi and Marathi (Devanagari), Bengali, Punjabi (Gurmukhi), Gujarati, Odia, Telugu, Kannada, Malayalam.
// ICU's Any-Latin gives ISO 15919 ("pyāra", "dila"), which Latin-ASCII flattens to "pyara", "dila"; songs are
// written "pyaar", "dil". So long vowels are doubled (aa, ee, oo), the retroflex and dental pairs share
// their letters (t, d, n), ś ṣ are "sh", c is "ch", ḻ is "zh", and the inherent vowel follows the
// language: Hindi, Bengali, Punjabi and Gujarati drop it where it is not sounded (dil, dhadkan, samajhnaa),
// the Dravidian languages keep it, and Malayalam's word-final virama is the "u" it is sung as.
//
// Every one of these blocks lays its letters out the same way (from ISCII), so one table serves all of
// them, by offset from the block's start. Plain C over UTF-16, tested off the phone:
// clang -x c -DSG_INDIC_TEST this file.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef enum { IND_OTHER, IND_VOWEL, IND_CONS, IND_SIGN } ind_kind;

typedef struct {
    ind_kind kind;
    uint16_t base;          // the script's block (0x0900, 0x0980...), 0 for other text
    const char *letters;    // the consonant's or the vowel's letters, or the sign's
    const char *vowel;      // IND_CONS: its vowel, NULL for none (virama), "" for a dropped inherent one
    int inherent;           // IND_CONS: the vowel is the inherent one, not written
    uint16_t other;         // IND_OTHER: the character
    uint16_t offset;        // IND_CONS: the consonant's offset in its block
} ind_unit;

static uint16_t ind_base(uint16_t c) {
    if (c >= 0x0900 && c <= 0x0D7F && !(c >= 0x0B80 && c <= 0x0BFF)) return c & 0xFF80;
    return 0;
}

static int ind_dravidian(uint16_t base) { return base == 0x0C00 || base == 0x0C80 || base == 0x0D00; }
// Where the inherent vowel goes unsounded at the end of a word and between some consonants.
static int ind_dropsSchwa(uint16_t base) { return base == 0x0900 || base == 0x0980 || base == 0x0A00 || base == 0x0A80; }

static const char *ind_consonant(uint16_t base, uint16_t o) {
    int dravidian = ind_dravidian(base);
    switch (o) {
        case 0x15: return "k";  case 0x16: return "kh"; case 0x17: return "g";  case 0x18: return "gh";
        case 0x19: return dravidian ? "ng" : "n";
        case 0x1A: return "ch"; case 0x1B: return "chh"; case 0x1C: return "j"; case 0x1D: return "jh";
        case 0x1E: return dravidian ? "nj" : "n";
        case 0x1F: return "t";  case 0x20: return "th"; case 0x21: return "d";  case 0x22: return "dh"; case 0x23: return "n";
        case 0x24: return "t";  case 0x25: return "th"; case 0x26: return "d";  case 0x27: return "dh"; case 0x28: return "n";
        case 0x29: return "n";
        case 0x2A: return "p";  case 0x2B: return "ph"; case 0x2C: return "b";  case 0x2D: return "bh"; case 0x2E: return "m";
        case 0x2F: return base == 0x0980 ? "j" : "y";   // Bengali য is sung j
        case 0x30: return "r";  case 0x31: return "r";  case 0x32: return "l";  case 0x33: return "l";  case 0x34: return "zh";
        case 0x35: return base == 0x0980 ? "b" : "v";   // Bengali has no v of its own
        case 0x36: return "sh"; case 0x37: return "sh"; case 0x38: return "s";  case 0x39: return "h";
        // The nukta letters written as one (Devanagari क़ ख़ ग़ ज़ ड़ ढ़ फ़ य़; Bengali ড় ঢ় য়).
        case 0x58: return "q";  case 0x59: return "kh"; case 0x5A: return "gh"; case 0x5B: return "z";
        case 0x5C: return base == 0x0980 ? "r" : "r";   case 0x5D: return "rh";
        case 0x5E: return "f";  case 0x5F: return "y";
    }
    return NULL;
}

// The same consonant with a nukta (़) after it.
static const char *ind_nukta(uint16_t o, const char *plain) {
    switch (o) {
        case 0x15: return "q"; case 0x16: return "kh"; case 0x17: return "gh"; case 0x1C: return "z";
        case 0x21: return "r"; case 0x22: return "rh"; case 0x2B: return "f"; case 0x2F: return "y";
    }
    return plain;
}

static const char *ind_independent(uint16_t o) {
    switch (o) {
        case 0x05: return "a";  case 0x06: return "aa"; case 0x07: return "i";  case 0x08: return "ee";
        case 0x09: return "u";  case 0x0A: return "oo"; case 0x0B: return "ri"; case 0x0C: return "li";
        case 0x0D: case 0x0E: case 0x0F: return "e"; case 0x10: return "ai";
        case 0x11: case 0x12: case 0x13: return "o"; case 0x14: return "au";
        case 0x60: return "ri";
    }
    return NULL;
}

static const char *ind_sign(uint16_t o) {
    switch (o) {
        case 0x3E: return "aa"; case 0x3F: return "i";  case 0x40: return "ee"; case 0x41: return "u";
        case 0x42: return "oo"; case 0x43: case 0x44: return "ri";
        case 0x45: case 0x46: case 0x47: return "e"; case 0x48: return "ai";
        case 0x49: case 0x4A: case 0x4B: return "o"; case 0x4C: return "au";
        case 0x57: return "au";   // Telugu ై / Malayalam ൗ length mark
        case 0x62: case 0x63: return "li";
    }
    return NULL;
}

// Malayalam's chillus, consonants with no vowel written as one letter.
static const char *ind_chillu(uint16_t c) {
    switch (c) {
        case 0x0D7A: case 0x0D7B: return "n"; case 0x0D7C: return "r"; case 0x0D7D: case 0x0D7E: return "l";
        case 0x0D7F: return "k"; case 0x0D54: return "m"; case 0x0D55: return "y"; case 0x0D56: return "zh";
    }
    return NULL;
}

static size_t ind_parse(const uint16_t *in, size_t n, ind_unit *units) {
    size_t count = 0;
    for (size_t i = 0; i < n; i++) {
        uint16_t c = in[i], base = ind_base(c), o = (uint16_t)(c - base);
        ind_unit u = {IND_OTHER, base, NULL, NULL, 0, c, 0};
        const char *cons = base ? ind_consonant(base, o) : NULL;
        if (base == 0x0D00 && ind_chillu(c)) {
            u.kind = IND_CONS; u.letters = ind_chillu(c); u.vowel = NULL;
        } else if (cons && !(o >= 0x3E && o <= 0x4D)) {
            u.kind = IND_CONS;
            u.letters = cons;
            u.offset = o;
            u.vowel = "a";
            u.inherent = 1;
            if (i + 1 < n && in[i + 1] == base + 0x3C) { u.letters = ind_nukta(o, cons); i++; }
            if (i + 1 < n && ind_base(in[i + 1]) == base) {
                uint16_t s = (uint16_t)(in[i + 1] - base);
                if (s == 0x4D) { u.vowel = NULL; u.inherent = 0; i++; }
                else if (ind_sign(s)) {
                    u.vowel = ind_sign(s); u.inherent = 0; i++;
                    // A vowel sign written in two parts (Malayalam ൊ as െ ാ, Bengali ো as ে া, Kannada, Telugu).
                    if (i + 1 < n && ind_base(in[i + 1]) == base) {
                        uint16_t t = (uint16_t)(in[i + 1] - base);
                        if ((s == 0x46 || s == 0x47) && (t == 0x3E || t == 0x57 || t == 0x55 || t == 0x56)) { u.vowel = t == 0x57 ? "au" : "o"; i++; }
                    }
                }
            }
        } else if (base && ind_independent(o)) {
            u.kind = IND_VOWEL; u.letters = ind_independent(o);
        } else if (base && (o == 0x01 || o == 0x02 || o == 0x03 || o == 0x70 || o == 0x71 || (base == 0x0980 && o == 0x4E))) {
            u.kind = IND_SIGN; u.offset = o;
        } else if (base && o >= 0x66 && o <= 0x6F) {
            u.other = (uint16_t)('0' + o - 0x66); u.base = 0;
        } else if (c == 0x0964 || c == 0x0965) {
            u.other = ','; u.base = 0;
        } else if (base) {
            u.kind = IND_SIGN; u.offset = 0xFFFF;   // a mark with nothing to say in Latin letters
        }
        units[count++] = u;
    }
    return count;
}

static int ind_sounded(const ind_unit *u) {
    return u->kind == IND_VOWEL || (u->kind == IND_CONS && u->vowel && u->vowel[0]);
}

// Hindi's unsounded a: the last one of a word of more than one letter, then, from the end, one that sits
// between a sounded letter and a consonant that keeps its own vowel (dha-da-ka-na: dhadkan).
static void ind_dropSchwas(ind_unit *units, size_t from, size_t to) {
    if (to - from < 2) return;
    ind_unit *last = &units[to - 1];
    if (last->kind == IND_CONS && last->inherent && ind_dropsSchwa(last->base)) last->vowel = "";
    for (size_t i = to - 1; i-- > from + 1;) {
        ind_unit *u = &units[i], *prev = &units[i - 1], *next = &units[i + 1];
        if (u->kind != IND_CONS || !u->inherent || !ind_dropsSchwa(u->base)) continue;
        if (!ind_sounded(prev) || next->kind != IND_CONS || !ind_sounded(next)) continue;
        u->vowel = "";
        i--;   // never two in a row
    }
}

static size_t ind_put(char *out, size_t at, size_t cap, const char *s) {
    size_t len = strlen(s);
    if (at + len < cap) memcpy(out + at, s, len);
    return at + len;
}

static size_t ind_putOther(char *out, size_t at, size_t cap, uint16_t c) {
    char b[4];
    size_t len;
    if (c < 0x80) { b[0] = (char)c; len = 1; }
    else if (c < 0x800) { b[0] = (char)(0xC0 | (c >> 6)); b[1] = (char)(0x80 | (c & 0x3F)); len = 2; }
    else { b[0] = (char)(0xE0 | (c >> 12)); b[1] = (char)(0x80 | ((c >> 6) & 0x3F)); b[2] = (char)(0x80 | (c & 0x3F)); len = 3; }
    if (at + len < cap) memcpy(out + at, b, len);
    return at + len;
}

static int ind_isLabial(const ind_unit *u) {
    return u && u->kind == IND_CONS && (u->offset == 0x2A || u->offset == 0x2B || u->offset == 0x2C || u->offset == 0x2D || u->offset == 0x2E);
}

// A long vowel ending a word is written short in Hindi, Bengali, Punjabi and Gujarati songs (mera, kabhi,
// zindagi), but kept in a word of one letter (naa, hee is still hi).
static const char *ind_finalVowel(const ind_unit *units, size_t i, const char *vowel) {
    const ind_unit *u = &units[i];
    if (!ind_dropsSchwa(u->base)) return vowel;
    if (!strcmp(vowel, "ee")) return "i";
    int alone = i == 0 || units[i - 1].base != u->base;
    if (alone) return vowel;
    if (!strcmp(vowel, "aa")) return "a";
    if (!strcmp(vowel, "oo")) return "u";
    return vowel;
}

static size_t SGIndicRead(const uint16_t *in, size_t n, char *out, size_t cap, ind_unit *units) {
    size_t count = ind_parse(in, n, units), at = 0;
    // Words are runs of one script's letters.
    for (size_t i = 0; i < count;) {
        if (!units[i].base) { i++; continue; }
        size_t j = i;
        while (j < count && units[j].base == units[i].base) j++;
        ind_dropSchwas(units, i, j);
        i = j;
    }
    for (size_t i = 0; i < count; i++) {
        const ind_unit *u = &units[i], *next = i + 1 < count ? &units[i + 1] : NULL;
        int wordEnd = !next || next->base != u->base;
        switch (u->kind) {
            case IND_CONS:
                // Punjabi's addak doubles the consonant after it.
                if (i > 0 && units[i - 1].kind == IND_SIGN && units[i - 1].offset == 0x71) at = ind_put(out, at, cap, u->letters);
                at = ind_put(out, at, cap, u->letters);
                if (u->vowel) at = ind_put(out, at, cap, wordEnd ? ind_finalVowel(units, i, u->vowel) : u->vowel);
                // Malayalam sings a word-final virama as u (ishtamaanu).
                else if (u->base == 0x0D00 && wordEnd && u->offset) at = ind_put(out, at, cap, "u");
                break;
            case IND_VOWEL:
                at = ind_put(out, at, cap, u->letters);
                break;
            case IND_SIGN:
                if (u->offset == 0x01 || u->offset == 0x70) at = ind_put(out, at, cap, "n");
                else if (u->offset == 0x02) {
                    // Anusvara: m before p b m, and word-final in the Dravidian languages (andam); n otherwise (main, hain).
                    at = ind_put(out, at, cap, ind_isLabial(next) || (wordEnd && ind_dravidian(u->base)) ? "m" : "n");
                } else if (u->offset == 0x03) at = ind_put(out, at, cap, "h");
                else if (u->offset == 0x4E) at = ind_put(out, at, cap, "t");   // Bengali ৎ
                break;
            case IND_OTHER:
                at = ind_putOther(out, at, cap, u->other);
                break;
        }
    }
    if (cap) out[at < cap ? at : cap - 1] = 0;
    return at;
}

#ifdef __OBJC__
#import "Lyrics.h"

NSString *SGIndicReading(NSString *text) {
    if ([text rangeOfString:@"[\\u0900-\\u0B7F\\u0C00-\\u0D7F]" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    NSString *composed = text.precomposedStringWithCanonicalMapping;
    NSUInteger n = composed.length;
    uint16_t *in = malloc(n * sizeof(uint16_t));
    ind_unit *units = malloc(n * sizeof(ind_unit));
    size_t cap = n * 4 + 16;
    char *out = malloc(cap);
    [composed getCharacters:in range:NSMakeRange(0, n)];
    SGIndicRead(in, n, out, cap, units);
    NSString *reading = [NSString stringWithUTF8String:out];
    free(in);
    free(units);
    free(out);
    return reading;
}
#endif

#ifdef SG_INDIC_TEST
#include <stdio.h>
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
        ind_unit units[4096];
        char out[16384];
        SGIndicRead(in, n, out, sizeof out, units);
        puts(out);
    }
    return 0;
}
#endif
