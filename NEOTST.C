/* Self-test program. The rows run one scan byte through neo_handle.
   Two further cases check the typeahead ring and the 83-key Ctrl key.
   init in NEO.ASM calls neo_main, which runs the cases and exits.
   This program is linked as NEOTST.COM. It is not part of NEO.COM.

   Turbo C 2.01, tiny model, 8086 only. The calls are the wrappers in
   NEO.ASM. A string passed to print() ends in $ because INT 21h AH=09h
   prints until that byte. */

#define NCASE 63

extern unsigned char key83, mod3a, mod3b, mod4a, mod4b;
extern unsigned char caps, suspended, seen_e0, npending, model_byte;
extern unsigned pending0, pending1;

void dos_exit(int code);
void putch(int c);
void print(char *s);
unsigned char peekb(unsigned seg, unsigned off);
void pokeb(unsigned seg, unsigned off, int val);
unsigned peekw(unsigned seg, unsigned off);
void pokew(unsigned seg, unsigned off, unsigned val);
int run_scan(int scan);
int store_word(unsigned word);
int has_4f(void);

/* One self-test row. pass is 1 when the BIOS should keep the scan.
   npending is how many typeahead words should be waiting. The words are
   the character in the low byte and the scan in the high byte. */
struct keycase {
    unsigned char scan;
    unsigned char flags17;
    unsigned char mod3a;
    unsigned char mod3b;
    unsigned char mod4a;
    unsigned char mod4b;
    unsigned char caps;
    unsigned char suspended;
    unsigned char key83;
    unsigned char seen_e0;
    unsigned char pass;
    unsigned char npending;
    unsigned pending0;
    unsigned pending1;
    unsigned char exp_flags17;
    unsigned char exp_caps;
    unsigned char exp_mod3a;
    unsigned char exp_mod3b;
    unsigned char exp_mod4a;
    unsigned char exp_mod4b;
    unsigned char exp_suspended;
    char *name;
};

/* Initializer columns, in order. The rows are positional.
   scan is the scan byte. flags17 is the byte at 0040:0017 before the
   call. Bit 0 is right Shift, bit 1 is left Shift, bit 2 is Ctrl,
   bit 3 is Alt, bit 6 is Caps Lock, and bit 7 is Insert. Then mod3a,
   mod3b, mod4a, mod4b, caps, suspended, key83, seen_e0. pass is 1 when
   the BIOS keeps the scan. Then npending, pending0, pending1,
   exp_flags17, exp_caps, exp_mod3a, exp_mod3b, exp_mod4a, exp_mod4b,
   exp_suspended, name. */
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
    { 0x2A, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x42, 1, 0, 0, 0, 0, 0, "shift-repeat\r\n$" },
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
    { 0x20, 0x00, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0x0000, 0x0000, 0x00, 0, 0, 0, 0, 0, 1, "suspended-letter\r\n$" },
    { 0x2A, 0x02, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0x0000, 0x0000, 0x02, 0, 0, 0, 0, 0, 0, "phantom-shift\r\n$" },
    { 0x2A, 0x03, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0x0000, 0x0000, 0x03, 0, 0, 0, 0, 0, 0, "both-shifts\r\n$" },
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

static void report(ok, name)
int ok;
char *name;
{
    if (ok)
        print("OK  $");
    else
        print("FAIL $");
    print(name);
}

static int one_case(c)
struct keycase *c;
{
    int ok;
    int carry;

    pokeb(0x40, 0x17, c->flags17);
    pokeb(0x40, 0x18, 0);
    mod3a = c->mod3a;
    mod3b = c->mod3b;
    mod4a = c->mod4a;
    mod4b = c->mod4b;
    caps = c->caps;
    suspended = c->suspended;
    key83 = c->key83;
    seen_e0 = c->seen_e0;
    carry = run_scan(c->scan);
    ok = 1;
    if (carry != c->pass)
        ok = 0;
    if (npending != c->npending)
        ok = 0;
    if (c->npending != 0 && pending0 != c->pending0)
        ok = 0;
    if (c->npending >= 2 && pending1 != c->pending1)
        ok = 0;
    if (peekb(0x40, 0x17) != c->exp_flags17)
        ok = 0;
    if (caps != c->exp_caps)
        ok = 0;
    if (mod3a != c->exp_mod3a)
        ok = 0;
    if (mod3b != c->exp_mod3b)
        ok = 0;
    if (mod4a != c->exp_mod4a)
        ok = 0;
    if (mod4b != c->exp_mod4b)
        ok = 0;
    if (suspended != c->exp_suspended)
        ok = 0;
    report(ok, c->name);
    return ok;
}

static int typeahead_case()
{
    unsigned tail;
    unsigned saved;
    int ok;

    tail = peekw(0x40, 0x1C);
    saved = peekw(0x40, tail);
    ok = 0;
    if (store_word(0xABCD) == 0) {
        if (peekw(0x40, tail) == 0xABCD)
            ok = 1;
        pokew(0x40, tail, saved);
        pokew(0x40, 0x1C, tail);
    }
    report(ok, "typeahead\r\n$");
    return ok;
}

/* On the 83-key positions, scan 3Ah sets the two Ctrl bits and the break
   BAh clears them. The carry flag is not part of this check. */
static int xt_ctrl_case()
{
    int ok;

    pokeb(0x40, 0x17, 0);
    pokeb(0x40, 0x18, 0);
    key83 = 1;
    seen_e0 = 0;
    suspended = 0;
    ok = 1;
    run_scan(0x3A);
    if (peekb(0x40, 0x17) != 0x04)
        ok = 0;
    if (peekb(0x40, 0x18) != 0x01)
        ok = 0;
    run_scan(0xBA);
    if (peekb(0x40, 0x17) != 0)
        ok = 0;
    if (peekb(0x40, 0x18) != 0)
        ok = 0;
    report(ok, "xt-ctrl\r\n$");
    return ok;
}

static void print_dec(n)
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

/* The model byte and the 4Fh line describe this machine. The cases
   do not use them. */
static int self_test()
{
    int bios_4f;
    unsigned char save17;
    unsigned char save18;
    int i;
    int passes;
    int fails;

    model_byte = peekb(0xF000, 0xFFFE);
    bios_4f = has_4f();
    print("Model $");
    hexbyte(model_byte);
    print("\r\n$");
    if (bios_4f)
        print("INT 15h/4Fh yes\r\n$");
    else
        print("INT 15h/4Fh no\r\n$");
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
    if (typeahead_case())
        passes = passes + 1;
    else
        fails = fails + 1;
    if (xt_ctrl_case())
        passes = passes + 1;
    else
        fails = fails + 1;
    pokeb(0x40, 0x17, save17);
    pokeb(0x40, 0x18, save18);
    print("passed $");
    print_dec(passes);
    print(" failed $");
    print_dec(fails);
    print("\r\n$");
    if (fails)
        return 1;
    return 0;
}

void neo_main()
{
    dos_exit(self_test());
}
