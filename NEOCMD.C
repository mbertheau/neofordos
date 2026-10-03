/* Commands, messages, and the self-test.
   NEO.ASM still owns every keystroke, and it still installs and
   removes the resident copy. Those two steps close handles and move
   the stack, which has to stay exact. This file is the part that
   decides which command to run and what to print.

   Turbo C 2.01, tiny model, 8086 only. There is no C runtime. The
   wrappers in NEO.ASM do the DOS and BIOS calls. A string passed to
   say() ends in $ because INT 21h AH=09h prints until that byte. */

#define NCASE 63

/* Bytes past neo_state in a copy that is already resident. */
#define ST_MOD3A  1
#define ST_MOD3B  2
#define ST_MOD4A  3
#define ST_MOD4B  4
#define ST_CAPS   5
#define ST_PAUSED 6
#define ST_HITS   14
#define ST_EATEN  16

extern unsigned char fingers, mod3a, mod3b, mod4a, mod4b;
extern unsigned char caps, paused, seen_e0, nout, modelb;
extern unsigned nword0, nword1;

void dos_exit(int code);
void putch(int c);
void say(char *s);
unsigned char peekb(unsigned seg, unsigned off);
void pokeb(unsigned seg, unsigned off, int val);
unsigned peekw(unsigned seg, unsigned off);
void pokew(unsigned seg, unsigned off, unsigned val);
int try_key(int scan);
int try_put(unsigned word);
void vec_at(unsigned vec, unsigned *off, unsigned *seg);
int bios_c0(void);
void do_unload(unsigned seg, unsigned entry);
void go_resident(int use15);

/* One self-test row. pass is 1 when the BIOS should keep the scan.
   nout is how many typeahead words should be waiting. The words are
   the character in the low byte and the scan in the high byte. */
struct keycase {
    unsigned char scan;
    unsigned char f17;
    unsigned char m3a;
    unsigned char m3b;
    unsigned char m4a;
    unsigned char m4b;
    unsigned char caps;
    unsigned char paused;
    unsigned char fingers;
    unsigned char e0;
    unsigned char pass;
    unsigned char nout;
    unsigned w0;
    unsigned w1;
    unsigned char e17;
    unsigned char ecap;
    unsigned char em3a;
    unsigned char em3b;
    unsigned char em4a;
    unsigned char em4b;
    unsigned char epau;
    char *name;
};

static struct keycase cases[NCASE] = {
    { 0x20, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x2061, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "a\r\n$" },
    { 0x20, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x2041, 0x0000, 0x01, 0, 0, 0, 0, 0, 0, "A\r\n$" },
    { 0x20, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x207B, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "lbrace\r\n$" },
    { 0x20, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x5000, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "down\r\n$" },
    { 0x13, 0x04, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x1303, 0x0000, 0x04, 0, 0, 0, 0, 0, 0, "ctrl-c\r\n$" },
    { 0x12, 0x04, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x120C, 0x0000, 0x04, 0, 0, 0, 0, 0, 0, "ctrl-l\r\n$" },
    { 0x1A, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0x1A53, 0x1A53, 0x01, 0, 0, 0, 0, 0, 0, "SS\r\n$" },
    { 0x02, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x02F8, 0x0000, 0x01, 0, 0, 0, 0, 0, 0, "degree\r\n$" },
    { 0x03, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x0315, 0x0000, 0x01, 0, 0, 0, 0, 0, 0, "section\r\n$" },
    { 0x2E, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x2E84, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "ae\r\n$" },
    { 0x2E, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x2E8E, 0x0000, 0x01, 0, 0, 0, 0, 0, 0, "AE\r\n$" },
    { 0x2C, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x2C81, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "ue\r\n$" },
    { 0x10, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x1078, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "x\r\n$" },
    { 0x2A, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x42, 1, 0, 0, 0, 0, 0, "caps-chord\r\n$" },
    { 0x3A, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0000, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "mod3-down\r\n$" },
    { 0x0BA, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "mod3-up\r\n$" },
    { 0x39, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x5230, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "kp0\r\n$" },
    { 0x16, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x4737, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "kp7\r\n$" },
    { 0x20, 0x00, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0x2041, 0x0000, 0x00, 1, 0, 0, 0, 0, 0, "caps-a\r\n$" },
    { 0x20, 0x01, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0x2061, 0x0000, 0x01, 1, 0, 0, 0, 0, 0, "caps-shift-a\r\n$" },
    { 0x14, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x145E, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "caret\r\n$" },
    { 0x0C, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x0C2D, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "hyphen\r\n$" },
    { 0x20, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x2000, 0x0000, 0x08, 0, 0, 0, 0, 0, 0, "alt-pos\r\n$" },
    { 0x2F, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x1C0D, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "enter\r\n$" },
    { 0x2C, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x011B, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "esc\r\n$" },
    { 0x11, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x0E08, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "backspace\r\n$" },
    { 0x3B, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "f1\r\n$" },
    { 0x1D, 0x00, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0x0000, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "xt-mod3\r\n$" },
    { 0x1D, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "at-ctrl\r\n$" },
    { 0x38, 0x00, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 1, 0, "altgr\r\n$" },
    { 0x38, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "left-alt\r\n$" },
    { 0x20, 0x0C, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x0C, 0, 0, 0, 0, 0, 0, "ctrl-alt\r\n$" },
    { 0x20, 0x04, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x207B, 0x0000, 0x04, 0, 1, 0, 0, 0, 0, "mod3-over-ctrl\r\n$" },
    { 0x04, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0000, 0x0000, 0x01, 0, 0, 0, 0, 0, 0, "shift-3\r\n$" },
    { 0x05, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x05AF, 0x0000, 0x01, 0, 0, 0, 0, 0, 0, "raquo\r\n$" },
    { 0x2E, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x2E7C, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "pipe\r\n$" },
    { 0x2E, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x5200, 0x0000, 0x80, 0, 0, 0, 1, 0, 0, "insert\r\n$" },
    { 0x2B, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0000, 0x0000, 0x00, 0, 1, 1, 0, 0, 1, "suspend\r\n$" },
    { 0x20, 0x00, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 1, "paused-letter\r\n$" },
    { 0x2A, 0x02, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0x0000, 0x0000, 0x02, 0, 0, 0, 0, 0, 0, "phantom-shift\r\n$" },
    { 0x2A, 0x03, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x03, 0, 0, 0, 0, 0, 0, "shift-repeat\r\n$" },
    { 0x0A0, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "letter-break\r\n$" },
    { 0x0E0, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "prefix\r\n$" },
    { 0x27, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x272C, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "comma\r\n$" },
    { 0x28, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x2840, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "at\r\n$" },
    { 0x28, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x282E, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "dot\r\n$" },
    { 0x03, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x03FD, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "sup2\r\n$" },
    { 0x20, 0x01, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x20E0, 0x0000, 0x01, 0, 1, 0, 0, 0, 0, "alpha\r\n$" },
    { 0x09, 0x00, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x09EC, 0x0000, 0x00, 0, 1, 0, 1, 0, 0, "inf\r\n$" },
    { 0x11, 0x00, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x11FB, 0x0000, 0x00, 0, 1, 0, 1, 0, 0, "sqrt\r\n$" },
    { 0x4F, 0x01, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x4FF3, 0x0000, 0x01, 0, 1, 0, 0, 0, 0, "le\r\n$" },
    { 0x51, 0x01, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x51F2, 0x0000, 0x01, 0, 1, 0, 0, 0, 0, "ge\r\n$" },
    { 0x4E, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x4EF1, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "plusminus\r\n$" },
    { 0x39, 0x01, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x39FF, 0x0000, 0x01, 0, 1, 0, 0, 0, 0, "nbsp\r\n$" },
    { 0x02, 0x00, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x02AA, 0x0000, 0x00, 0, 1, 0, 1, 0, 0, "not\r\n$" },
    { 0x35, 0x00, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0x35F6, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "divide\r\n$" },
    { 0x35, 0x00, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "kp-slash\r\n$" },
    { 0x47, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 0, "kp7-bios\r\n$" },
    { 0x09, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x0F09, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "tab\r\n$" },
    { 0x48, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x4800, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "kp-up\r\n$" },
    { 0x4C, 0x00, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x4C00, 0x0000, 0x00, 0, 0, 0, 1, 0, 0, "kp-begin\r\n$" },
    { 0x1A, 0x00, 0, 0, 0, 0, 1, 0, 0, 0, 0, 2, 0x1A53, 0x1A53, 0x00, 1, 0, 0, 0, 0, 0, "caps-sz\r\n$" },
    { 0x1B, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x1B2F, 0x0000, 0x00, 0, 1, 0, 0, 0, 0, "slash\r\n$" },
};

static char help_txt[] =
    "Neo keyboard, code page 437.\r\n"
    "NEO        install\r\n"
    "NEO /U     remove\r\n"
    "NEO /T     self-test\r\n"
    "NEO /XT    83-key finger positions\r\n"
    "NEO /AT    102-key finger positions\r\n"
    "$";

static void putu(n)
unsigned n;
{
    char digs[5];
    int i;
    unsigned q;
    unsigned r;

    if (n == 0) {
        putch('0');
        return;
    }
    i = 0;
    while (n != 0) {
        q = 0;
        r = n;
        while (r >= 10) {
            r = r - 10;
            q = q + 1;
        }
        digs[i] = (char)('0' + r);
        i = i + 1;
        n = q;
    }
    while (i != 0) {
        i = i - 1;
        putch(digs[i]);
    }
}

static char hexdig(n)
unsigned n;
{
    if (n < 10)
        return (char)('0' + n);
    return (char)('A' + (n - 10));
}

/* Two hex digits. Subtracting 16 keeps the compiler off a shift by a
   count, which the 8086 cannot do as one instruction. */
static void hexbyte(b)
unsigned b;
{
    unsigned hi;

    hi = 0;
    while (b >= 16) {
        b = b - 16;
        hi = hi + 1;
    }
    putch(hexdig(hi));
    putch(hexdig(b));
}

static void onoff(v)
unsigned v;
{
    if (v)
        say("on$");
    else
        say("off$");
}

/* Model bytes FF, FE, FD, and FB use the 83-key finger positions.
   Every other model byte uses the 102-key positions. The return value
   is 1 when the BIOS calls INT 15h AH=4Fh. */
static int detect()
{
    unsigned char model;

    model = peekb(0xF000, 0xFFFE);
    modelb = model;
    fingers = 0;
    if (model == 0xFF || model == 0xFE || model == 0xFD || model == 0xFB)
        fingers = 1;
    return bios_c0();
}

static int is_neo(seg, off)
unsigned seg;
unsigned off;
{
    unsigned at;

    at = off - 6;
    if (peekb(seg, at) != 'N')
        return 0;
    if (peekb(seg, at + 1) != 'E')
        return 0;
    if (peekb(seg, at + 2) != 'O')
        return 0;
    if (peekb(seg, at + 3) != '2')
        return 0;
    return 1;
}

/* Look on INT 15h first, then on INT 09h. A hit returns the segment
   and the offset of the hooked entry. */
static int find_res(segp, entryp)
unsigned *segp;
unsigned *entryp;
{
    unsigned seg;
    unsigned off;

    vec_at(0x15, &off, &seg);
    if (is_neo(seg, off)) {
        *segp = seg;
        *entryp = off;
        return 1;
    }
    vec_at(0x09, &off, &seg);
    if (is_neo(seg, off)) {
        *segp = seg;
        *entryp = off;
        return 1;
    }
    return 0;
}

static void show_status(seg, entry)
unsigned seg;
unsigned entry;
{
    unsigned state;
    unsigned mods;

    state = peekw(seg, entry - 2);
    say("Neo is already resident.\r\nCalls $");
    putu(peekw(seg, state + ST_HITS));
    say(", kept $");
    putu(peekw(seg, state + ST_EATEN));
    say("\r\nCaps $");
    onoff(peekb(seg, state + ST_CAPS));
    say("  Pause $");
    onoff(peekb(seg, state + ST_PAUSED));
    say("  Mod3 $");
    mods = peekb(seg, state + ST_MOD3A);
    mods = mods | peekb(seg, state + ST_MOD3B);
    onoff(mods);
    say("  Mod4 $");
    mods = peekb(seg, state + ST_MOD4A);
    mods = mods | peekb(seg, state + ST_MOD4B);
    onoff(mods);
    say("\r\nNEO /U removes it.\r\n$");
}

/* Printed while standard output is still open. go_resident closes
   handles 0 through 19 after this returns. */
static void announce(has4f)
int has4f;
{
    say("Neo is resident. Code page 437.\r\n$");
    if (fingers == 0)
        say("Mod3: Caps Lock and the # key. Mod4: the < key and AltGr.\r\n$");
    else {
        say("83-key: Mod3 is the key left of A and the # key.\r\n$");
        say("Mod4 is Alt. Ctrl is the wide key right of the space bar.\r\n$");
    }
    if (has4f)
        say("Hooked INT 15h AH=4Fh.\r\n$");
    else
        say("Hooked INT 09h. The BIOS still handles every other key.\r\n$");
    say("Both Shift keys: capitals. Both Mod3 keys: suspend.\r\n$");
    say("NEO /U removes it. Run NEO again to see the counters.\r\n$");
}

static void report(ok, name)
int ok;
char *name;
{
    if (ok)
        say("OK  $");
    else
        say("FAIL $");
    say(name);
}

static int one_case(c)
struct keycase *c;
{
    int ok;
    int carry;

    pokeb(0x40, 0x17, c->f17);
    pokeb(0x40, 0x18, 0);
    mod3a = c->m3a;
    mod3b = c->m3b;
    mod4a = c->m4a;
    mod4b = c->m4b;
    caps = c->caps;
    paused = c->paused;
    fingers = c->fingers;
    seen_e0 = c->e0;
    carry = try_key(c->scan);
    ok = 1;
    if (carry != c->pass)
        ok = 0;
    if (nout != c->nout)
        ok = 0;
    if (c->nout != 0 && nword0 != c->w0)
        ok = 0;
    if (c->nout >= 2 && nword1 != c->w1)
        ok = 0;
    if (peekb(0x40, 0x17) != c->e17)
        ok = 0;
    if (caps != c->ecap)
        ok = 0;
    if (mod3a != c->em3a)
        ok = 0;
    if (mod3b != c->em3b)
        ok = 0;
    if (mod4a != c->em4a)
        ok = 0;
    if (mod4b != c->em4b)
        ok = 0;
    if (paused != c->epau)
        ok = 0;
    report(ok, c->name);
    return ok;
}

static int buf_case()
{
    unsigned tail;
    unsigned saved;
    int ok;

    tail = peekw(0x40, 0x1C);
    saved = peekw(0x40, tail);
    ok = 0;
    if (try_put(0xABCD) == 0) {
        if (peekw(0x40, tail) == 0xABCD)
            ok = 1;
        pokew(0x40, tail, saved);
        pokew(0x40, 0x1C, tail);
    }
    report(ok, "buffer\r\n$");
    return ok;
}

/* On the 83-key map, scan 3Ah sets the two Ctrl bits and the break
   BAh clears them. The carry flag is not part of this check. */
static int xt_ctrl_case()
{
    int ok;

    pokeb(0x40, 0x17, 0);
    pokeb(0x40, 0x18, 0);
    fingers = 1;
    seen_e0 = 0;
    paused = 0;
    ok = 1;
    try_key(0x3A);
    if (peekb(0x40, 0x17) != 0x04)
        ok = 0;
    if (peekb(0x40, 0x18) != 0x01)
        ok = 0;
    try_key(0xBA);
    if (peekb(0x40, 0x17) != 0)
        ok = 0;
    if (peekb(0x40, 0x18) != 0)
        ok = 0;
    report(ok, "xt-ctrl\r\n$");
    return ok;
}

static int self_test()
{
    int has4f;
    unsigned char save17;
    unsigned char save18;
    int i;
    int passes;
    int fails;

    has4f = detect();
    say("Model $");
    hexbyte(modelb);
    say("\r\n$");
    if (has4f)
        say("INT 15h/4Fh yes\r\n$");
    else
        say("INT 15h/4Fh no\r\n$");
    save17 = peekb(0x40, 0x17);
    save18 = peekb(0x40, 0x18);
    passes = 0;
    fails = 0;
    for (i = 0; i < NCASE; i = i + 1) {
        if (one_case(&cases[i]))
            passes = passes + 1;
        else
            fails = fails + 1;
    }
    if (buf_case())
        passes = passes + 1;
    else
        fails = fails + 1;
    if (xt_ctrl_case())
        passes = passes + 1;
    else
        fails = fails + 1;
    pokeb(0x40, 0x17, save17);
    pokeb(0x40, 0x18, save18);
    say("passed $");
    putu(passes);
    say(" failed $");
    putu(fails);
    say("\r\n$");
    if (fails)
        return 1;
    return 0;
}

/* The command tail is at offset 80h of the PSP. In the tiny model that
   offset is a near pointer: DS is the PSP. A bad switch asks for the
   help text, and so does /H. /? becomes a bad switch after the letter
   fold and takes the same path. */
static void parse(help, test, unload, force)
int *help;
int *test;
int *unload;
int *force;
{
    unsigned char *tail;
    unsigned char *s;
    unsigned char *end;
    unsigned c;
    unsigned d;

    *help = 0;
    *test = 0;
    *unload = 0;
    *force = 0;
    tail = (unsigned char *)0x80;
    s = tail + 1;
    end = s + tail[0];
    while (s < end) {
        if (*s != '/') {
            s = s + 1;
            continue;
        }
        c = s[1] & 0xDF;
        if (c == 'U')
            *unload = 1;
        else if (c == 'T')
            *test = 1;
        else if (c == 'H')
            *help = 1;
        else if (c == 'X') {
            d = s[2] & 0xDF;
            if (d == 'T')
                *force = 1;
            else
                *help = 1;
        } else if (c == 'A') {
            d = s[2] & 0xDF;
            if (d == 'T')
                *force = 2;
            else
                *help = 1;
        } else
            *help = 1;
        s = s + 1;
        while (s < end && *s != ' ')
            s = s + 1;
    }
}

void neo_main()
{
    int help;
    int test;
    int unload;
    int force;
    unsigned seg;
    unsigned entry;
    int has4f;

    help = 0;
    test = 0;
    unload = 0;
    force = 0;
    parse(&help, &test, &unload, &force);
    if (help) {
        say(help_txt);
        dos_exit(0);
    }
    if (test)
        dos_exit(self_test());
    if (find_res(&seg, &entry)) {
        if (unload) {
            do_unload(seg, entry);
            say("Neo removed.\r\n$");
            dos_exit(0);
        }
        show_status(seg, entry);
        dos_exit(1);
    }
    if (unload) {
        say("Neo is not resident.\r\n$");
        dos_exit(1);
    }
    has4f = detect();
    if (force == 1)
        fingers = 1;
    if (force == 2)
        fingers = 0;
    announce(has4f);
    go_resident(has4f);
}
