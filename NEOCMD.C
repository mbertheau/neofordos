/* Commands and messages.
   NEO.ASM owns every keystroke, and it installs and removes the
   resident copy. This file decides which command to run and what
   to print.

   Turbo C 2.01, tiny model, 8086 only. There is no C runtime. The
   wrappers in NEO.ASM do the DOS and BIOS calls. A string passed to
   print() ends in $ because INT 21h AH=09h prints until that byte. */

/* Bytes past neo_state in a copy that is already resident. */
#define ST_MOD3A  1
#define ST_MOD3B  2
#define ST_MOD4A  3
#define ST_MOD4B  4
#define ST_CAPS   5
#define ST_SUSPENDED 6
#define ST_SCANS     14
#define ST_KEPT      16

extern unsigned char key83, model_byte;

void dos_exit(int code);
void putch(int c);
void print(char *s);
unsigned char peekb(unsigned seg, unsigned off);
unsigned peekw(unsigned seg, unsigned off);
void read_vector(unsigned vec, unsigned *off, unsigned *seg);
int has_4f(void);
void remove_neo(unsigned seg, unsigned entry);
void go_resident(int bios_4f);

static char help_txt[] =
    "Neo keyboard, code page 437.\r\n"
    "NEO        install\r\n"
    "NEO /U     remove\r\n"
    "NEO /XT    83-key positions\r\n"
    "NEO /AT    102-key positions\r\n"
    "$";

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

static void print_onoff(v)
unsigned v;
{
    if (v)
        print("on$");
    else
        print("off$");
}

/* Model bytes FF, FE, FD, and FB use the 83-key positions.
   Every other model byte uses the 102-key positions. The return value
   is 1 when the BIOS calls INT 15h AH=4Fh. */
static int detect()
{
    unsigned char model;

    model = peekb(0xF000, 0xFFFE);
    model_byte = model;
    key83 = 0;
    if (model == 0xFF || model == 0xFE || model == 0xFD || model == 0xFB)
        key83 = 1;
    return has_4f();
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
static int find_resident(segp, entryp)
unsigned *segp;
unsigned *entryp;
{
    unsigned seg;
    unsigned off;

    read_vector(0x15, &off, &seg);
    if (is_neo(seg, off)) {
        *segp = seg;
        *entryp = off;
        return 1;
    }
    read_vector(0x09, &off, &seg);
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
    print("Neo is already resident.\r\nScans $");
    print_dec(peekw(seg, state + ST_SCANS));
    print(", kept $");
    print_dec(peekw(seg, state + ST_KEPT));
    print("\r\nCaps $");
    print_onoff(peekb(seg, state + ST_CAPS));
    print("  Suspend $");
    print_onoff(peekb(seg, state + ST_SUSPENDED));
    print("  Mod3 $");
    mods = peekb(seg, state + ST_MOD3A);
    mods = mods | peekb(seg, state + ST_MOD3B);
    print_onoff(mods);
    print("  Mod4 $");
    mods = peekb(seg, state + ST_MOD4A);
    mods = mods | peekb(seg, state + ST_MOD4B);
    print_onoff(mods);
    print("\r\nNEO /U removes it.\r\n$");
}

/* Printed while standard output is still open. go_resident closes
   handles 0 through 19 after this returns. */
static void announce(bios_4f)
int bios_4f;
{
    print("Neo is resident. Code page 437.\r\n$");
    if (key83 == 0)
        print("Mod3: Caps Lock and the # key. Mod4: the < key and AltGr.\r\n$");
    else {
        print("83-key: Mod3 is the key left of A and the # key.\r\n$");
        print("Mod4 is Alt. Ctrl is the wide key right of the space bar.\r\n$");
    }
    if (bios_4f)
        print("Hooked INT 15h AH=4Fh.\r\n$");
    else
        print("Hooked INT 09h. The BIOS still handles every other key.\r\n$");
    print("Shift repeat: capitals. Both Mod3 keys: suspend.\r\n$");
    print("NEO /U removes it. Run NEO again to see the counters.\r\n$");
}

/* The command tail is at offset 80h of the PSP. In the tiny model that
   offset is a near pointer: DS is the PSP. A bad switch asks for the
   help text, and so does /H. /? becomes a bad switch after the letter
   fold and takes the same path. key83_arg stays -1 when the command
   does not choose positions. /XT sets it to 1 and /AT sets it to 0,
   the same values as key83. */
static void parse(help, remove, key83_arg)
int *help;
int *remove;
int *key83_arg;
{
    unsigned char *tail;
    unsigned char *s;
    unsigned char *end;
    unsigned c;
    unsigned d;

    *help = 0;
    *remove = 0;
    *key83_arg = -1;
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
            *remove = 1;
        else if (c == 'H')
            *help = 1;
        else if (c == 'X') {
            d = s[2] & 0xDF;
            if (d == 'T')
                *key83_arg = 1;
            else
                *help = 1;
        } else if (c == 'A') {
            d = s[2] & 0xDF;
            if (d == 'T')
                *key83_arg = 0;
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
    int remove;
    int key83_arg;
    unsigned seg;
    unsigned entry;
    int bios_4f;

    help = 0;
    remove = 0;
    key83_arg = -1;
    parse(&help, &remove, &key83_arg);
    if (help) {
        print(help_txt);
        dos_exit(0);
    }
    if (find_resident(&seg, &entry)) {
        if (remove) {
            remove_neo(seg, entry);
            print("Neo removed.\r\n$");
            dos_exit(0);
        }
        show_status(seg, entry);
        dos_exit(1);
    }
    if (remove) {
        print("Neo is not resident.\r\n$");
        dos_exit(1);
    }
    bios_4f = detect();
    if (key83_arg >= 0)
        key83 = key83_arg;
    announce(bios_4f);
    go_resident(bios_4f);
}
