/* main_win.c — Orovela Sample Manager, Win32 GUI.
 * Single self-contained executable: the Orovela 1.5 base disk is embedded
 * (BASE_DISK in base_disk.c) so "New Disk" needs no donor image.
 * Build: x86_64-w64-mingw32-gcc -O2 -mwindows -static ... -lcomctl32 -lcomdlg32 -lwinmm
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <mmsystem.h>
#include <stdio.h>
#include <string.h>
#include "hfe.h"
#include "slots.h"
#include "wavio.h"

#define APP_NAME    "Orovela Sample Manager"
#define APP_VERSION "1.0"

extern const unsigned char BASE_DISK[];
extern const unsigned int  BASE_DISK_LEN;

/* control IDs */
enum {
    ID_LIST = 100,
    ID_OPEN, ID_NEW, ID_SAVEAS,
    ID_PLAY, ID_WAV, ID_EXPORT, ID_IMPORT, ID_IMPWAV, ID_CLEAR,
    ID_STATUS
};

static HWND g_hwnd, g_list, g_status;
static HWND g_btn[9];
static HFE  g_disk;
static int  g_loaded = 0;      /* a disk is in memory */
static int  g_modified = 0;
static char g_path[MAX_PATH] = "";   /* "" = new, unsaved disk */
static uint8_t *g_playbuf = NULL;    /* WAV kept alive for PlaySound */
static int  g_playing_slot = -1;

size_t wav_build_pcm16(uint8_t *out, const uint8_t *sample, int n, int hz);

/* ---------------------------------------------------------------- helpers */

static void msg_err(const char *text)  { MessageBoxA(g_hwnd, text, APP_NAME, MB_OK | MB_ICONERROR); }
static void msg_info(const char *text) { MessageBoxA(g_hwnd, text, APP_NAME, MB_OK | MB_ICONINFORMATION); }

static void stop_play(void)
{
    if (g_playing_slot >= 0) {
        PlaySoundA(NULL, NULL, 0);
        g_playing_slot = -1;
    }
    if (g_playbuf) { free(g_playbuf); g_playbuf = NULL; }
    SetWindowTextA(g_btn[3], "Play");
}

static void set_title(void)
{
    char t[MAX_PATH + 64];
    const char *name = "no disk loaded";
    if (g_loaded) {
        if (g_path[0]) {
            name = strrchr(g_path, '\\');
            name = name ? name + 1 : g_path;
        } else {
            name = "new disk (unsaved)";
        }
    }
    wsprintfA(t, "%s %s \x97 %s%s", APP_NAME, APP_VERSION, name, g_modified ? " *" : "");
    SetWindowTextA(g_hwnd, t);
}

static void set_status(const char *s) { SetWindowTextA(g_status, s); }

static int selected_slot(void)
{
    return (int)SendMessageA(g_list, LVM_GETNEXTITEM, (WPARAM)-1, LVNI_SELECTED);
}

static void lv_set(int row, int col, const char *text)
{
    LVITEMA it;
    memset(&it, 0, sizeof it);
    it.iSubItem = col;
    it.pszText = (char *)text;
    SendMessageA(g_list, LVM_SETITEMTEXTA, (WPARAM)row, (LPARAM)&it);
}

static void refresh_list(void)
{
    for (int s = 0; s < SLOT_COUNT; s++) {
        char rate[40] = "\x97", loop[16] = "\x97", len[24] = "\x97";
        const char *contents = "\x97";
        if (g_loaded) {
            SlotInfo si;
            slot_info(&g_disk, s, &si);
            switch (si.kind) {
            case SLOT_EMPTY:   contents = "Empty"; break;
            case SLOT_V3:
                contents = si.has_sample ? "Program + sample" : "Program (no sample)";
                if (si.rate) {
                    wsprintfA(rate, "%d  (%d Hz)", si.rate, si.rate_hz);
                    if (si.has_sample) {
                        int tenths = (SAMPLE_BYTES * 10 + si.rate_hz / 2) / si.rate_hz;
                        wsprintfA(len, "%d.%d s", tenths / 10, tenths % 10);
                    }
                }
                lstrcpyA(loop, si.loop_on ? "On" : "Off");
                break;
            case SLOT_OLDVER:  contents = "Old format (incompatible)"; break;
            case SLOT_ANCIENT: contents = "Ancient patch slot"; break;
            case SLOT_INVALID: contents = "Invalid"; break;
            default:           contents = "Unreadable"; break;
            }
        }
        lv_set(s, 1, contents);
        lv_set(s, 2, rate);
        lv_set(s, 3, loop);
        lv_set(s, 4, len);
    }
    set_title();
}

static int confirm_discard(void)
{
    if (!g_modified) return 1;
    return MessageBoxA(g_hwnd,
        "The current disk has unsaved changes.\nDiscard them?",
        APP_NAME, MB_YESNO | MB_ICONWARNING) == IDYES;
}

/* ---------------------------------------------------------------- actions */

static void do_open(void)
{
    if (!confirm_discard()) return;
    char file[MAX_PATH] = "";
    OPENFILENAMEA ofn;
    memset(&ofn, 0, sizeof ofn);
    ofn.lStructSize = sizeof ofn;
    ofn.hwndOwner = g_hwnd;
    ofn.lpstrFilter = "HFE disk images (*.hfe)\0*.hfe\0All files\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = sizeof file;
    ofn.lpstrTitle = "Open Orovela disk image";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    if (!GetOpenFileNameA(&ofn)) return;

    HFE h;
    if (hfe_load(&h, file) != 0) {
        msg_err("Could not read that file as an HFE disk image.");
        return;
    }
    SetCursor(LoadCursorA(NULL, (LPCSTR)IDC_WAIT));
    int v = disk_validate_orovela(&h);
    SetCursor(LoadCursorA(NULL, (LPCSTR)IDC_ARROW));
    if (v == -1) {
        hfe_free(&h);
        msg_err("That HFE does not read as a Mirage disk\n(bad sector structure or CRC errors).");
        return;
    }
    if (v == -2) {
        hfe_free(&h);
        msg_err("That disk is not an Orovela disk.\n\nOnly Orovela disk images are supported\n(the stock Mirage OS uses a different format).");
        return;
    }
    stop_play();
    if (g_loaded) hfe_free(&g_disk);
    g_disk = h;
    g_loaded = 1;
    g_modified = 0;
    lstrcpynA(g_path, file, MAX_PATH);
    refresh_list();
    set_status("Disk loaded. Select a slot to extract, export, import or play.");
}

static void do_new(void)
{
    if (!confirm_discard()) return;
    HFE h;
    if (hfe_from_mem(&h, BASE_DISK, BASE_DISK_LEN) != 0) {
        msg_err("Internal error: embedded base disk failed to load.");
        return;
    }
    stop_play();
    if (g_loaded) hfe_free(&g_disk);
    g_disk = h;
    g_loaded = 1;
    g_modified = 0;
    g_path[0] = 0;
    refresh_list();
    set_status("New disk: Orovela 1.5, all 10 slots empty. Import .oro files, then Save Disk As.");
}

static void do_saveas(void)
{
    if (!g_loaded) { msg_info("No disk loaded."); return; }
    char file[MAX_PATH] = "DSKA0000_custom.hfe";
    OPENFILENAMEA ofn;
    memset(&ofn, 0, sizeof ofn);
    ofn.lStructSize = sizeof ofn;
    ofn.hwndOwner = g_hwnd;
    ofn.lpstrFilter = "HFE disk images (*.hfe)\0*.hfe\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = sizeof file;
    ofn.lpstrTitle = "Save disk image as";
    ofn.lpstrDefExt = "hfe";
    ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
    if (!GetSaveFileNameA(&ofn)) return;
    if (hfe_save(&g_disk, file) != 0) {
        msg_err("Could not write the disk image.");
        return;
    }
    lstrcpynA(g_path, file, MAX_PATH);
    g_modified = 0;
    refresh_list();
    set_status("Disk image saved. Flash it to a floppy-emulator image slot as usual.");
}

static int need_slot(SlotInfo *si)
{
    if (!g_loaded) { msg_info("No disk loaded. Open a disk or create a new one first."); return -1; }
    int s = selected_slot();
    if (s < 0) { msg_info("Select a slot first."); return -1; }
    if (si) slot_info(&g_disk, s, si);
    return s;
}

static void do_play(void)
{
    SlotInfo si;
    int s = need_slot(&si);
    if (s < 0) return;
    if (g_playing_slot == s) { stop_play(); set_status("Stopped."); return; }
    if (si.kind != SLOT_V3) { msg_info("This slot has no Orovela program to play."); return; }
    if (!si.has_sample) { msg_info("This program has no sample (boot wave patch)."); return; }
    stop_play();
    uint8_t *sample = (uint8_t *)malloc(SAMPLE_BYTES);
    if (!sample) return;
    if (slot_read_audio_playback(&g_disk, s, sample) != 0) { free(sample); msg_err("Could not read the sample sectors."); return; }
    g_playbuf = (uint8_t *)malloc(44 + 2 * SAMPLE_BYTES);
    if (!g_playbuf) { free(sample); return; }
    wav_build_pcm16(g_playbuf, sample, SAMPLE_BYTES, si.rate_hz ? si.rate_hz : rate_to_hz(3));
    free(sample);
    if (PlaySoundA((LPCSTR)g_playbuf, NULL, SND_MEMORY | SND_ASYNC | SND_NODEFAULT)) {
        g_playing_slot = s;
        SetWindowTextA(g_btn[3], "Stop");
        char st[64];
        wsprintfA(st, "Playing slot %d (full 32 KB buffer at capture rate).", s);
        set_status(st);
    }
}

static void save_dialog_for_slot(int s, const char *ext, const char *filter,
                                 const char *title, char *file)
{
    wsprintfA(file, "slot%d.%s", s, ext);
    OPENFILENAMEA ofn;
    memset(&ofn, 0, sizeof ofn);
    ofn.lStructSize = sizeof ofn;
    ofn.hwndOwner = g_hwnd;
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = title;
    ofn.lpstrDefExt = ext;
    ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
    if (!GetSaveFileNameA(&ofn)) file[0] = 0;
}

static void do_wav(void)
{
    SlotInfo si;
    int s = need_slot(&si);
    if (s < 0) return;
    if (si.kind != SLOT_V3) { msg_info("Only Orovela program slots can be extracted."); return; }
    if (!si.has_sample) { msg_info("This program has no sample to extract."); return; }
    char file[MAX_PATH];
    save_dialog_for_slot(s, "wav", "WAV audio (*.wav)\0*.wav\0", "Extract sample to WAV", file);
    if (!file[0]) return;
    if (slot_export_wav(&g_disk, s, file) != 0) { msg_err("WAV export failed."); return; }
    char st[96];
    wsprintfA(st, "Slot %d extracted to WAV (16-bit mono, %d Hz).", s, si.rate_hz);
    set_status(st);
}

static void do_export(void)
{
    SlotInfo si;
    int s = need_slot(&si);
    if (s < 0) return;
    if (si.kind != SLOT_V3) { msg_info("Only Orovela program slots can be exported as .oro."); return; }
    char file[MAX_PATH];
    save_dialog_for_slot(s, "oro", "Orovela programs (*.oro)\0*.oro\0", "Export slot as Orovela program", file);
    if (!file[0]) return;
    if (slot_export_oro(&g_disk, s, file) != 0) { msg_err(".oro export failed."); return; }
    char st[96];
    wsprintfA(st, "Slot %d exported as an Orovela program (.oro).", s);
    set_status(st);
}

static void do_import(void)
{
    SlotInfo si;
    int s = need_slot(&si);
    if (s < 0) return;
    if (si.kind != SLOT_EMPTY) {
        char q[128];
        wsprintfA(q, "Slot %d is not empty.\nOverwrite its contents?", s);
        if (MessageBoxA(g_hwnd, q, APP_NAME, MB_YESNO | MB_ICONWARNING) != IDYES) return;
    }
    char file[MAX_PATH] = "";
    OPENFILENAMEA ofn;
    memset(&ofn, 0, sizeof ofn);
    ofn.lStructSize = sizeof ofn;
    ofn.hwndOwner = g_hwnd;
    ofn.lpstrFilter = "Orovela programs (*.oro)\0*.oro\0All files\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = sizeof file;
    ofn.lpstrTitle = "Import Orovela program into slot";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    if (!GetOpenFileNameA(&ofn)) return;
    int rc = slot_import_oro(&g_disk, s, file);
    if (rc == -11)      msg_err("That is not a valid .oro file (wrong size).");
    else if (rc == -12) msg_err("That is not a valid .oro file (bad magic).");
    else if (rc == -13) msg_err("That .oro file does not contain an Orovela program (header v3, v4 or v5).");
    else if (rc != 0)   msg_err("Import failed while writing slot sectors.");
    if (rc != 0) return;
    g_modified = 1;
    refresh_list();
    char st[96];
    wsprintfA(st, "Program imported into slot %d. Save Disk As\x85 to write the image.", s);
    set_status(st);
}

static void do_impwav(void)
{
    SlotInfo si;
    int s = need_slot(&si);
    if (s < 0) return;
    if (si.kind != SLOT_EMPTY) {
        char q[128];
        wsprintfA(q, "Slot %d is not empty.\nOverwrite its contents?", s);
        if (MessageBoxA(g_hwnd, q, APP_NAME, MB_YESNO | MB_ICONWARNING) != IDYES) return;
    }
    char file[MAX_PATH] = "";
    OPENFILENAMEA ofn;
    memset(&ofn, 0, sizeof ofn);
    ofn.lStructSize = sizeof ofn;
    ofn.hwndOwner = g_hwnd;
    ofn.lpstrFilter = "WAV audio (*.wav)\0*.wav\0All files\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = sizeof file;
    ofn.lpstrTitle = "Import WAV into slot";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    if (!GetOpenFileNameA(&ofn)) return;

    FILE *f = fopen(file, "rb");
    if (!f) { msg_err("Could not open that WAV file."); return; }
    fseek(f, 0, SEEK_END);
    long fl = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = (uint8_t *)malloc((size_t)fl);
    WavImport *wi = (WavImport *)malloc(sizeof *wi);
    if (!buf || !wi || fread(buf, 1, (size_t)fl, f) != (size_t)fl) {
        fclose(f); free(buf); free(wi);
        msg_err("Could not read that WAV file.");
        return;
    }
    fclose(f);
    /* rate: auto by default; offer an override (needed for short/gritty
     * imports and for diagnostics) */
    int force = 0;
    {
        int r = MessageBoxA(g_hwnd,
            "Pick the sample rate automatically from the WAV's length?\n\n"
            "Yes = automatic (highest rate that fits)\n"
            "No  = choose a rate manually",
            APP_NAME, MB_YESNO | MB_ICONQUESTION);
        if (r == IDNO) {
            r = MessageBoxA(g_hwnd,
                "Use rate 4 (15504 Hz, 2.1 s window)?\n"
                "(rate 4 needs Orovela 1.4 or later)\n\n"
                "No = next: rate 3 / 2 / 1",
                APP_NAME, MB_YESNO | MB_ICONQUESTION);
            if (r == IDYES) force = 4;
            else {
                r = MessageBoxA(g_hwnd,
                    "Use rate 3 (10256 Hz, 3.2 s window)?\n\n"
                    "No = next: rate 2 / rate 1",
                    APP_NAME, MB_YESNO | MB_ICONQUESTION);
                if (r == IDYES) force = 3;
                else {
                    r = MessageBoxA(g_hwnd,
                        "Use rate 2 (6349 Hz, 5.2 s window)?\n\n"
                        "No = rate 1 (3419 Hz, 9.6 s window)",
                        APP_NAME, MB_YESNO | MB_ICONQUESTION);
                    force = (r == IDYES) ? 2 : 1;
                }
            }
        }
    }
    int rc = wav_import_build_rate(buf, (size_t)fl, force, wi);
    free(buf);
    if (rc != 0) {
        free(wi);
        msg_err(rc == -3 ? "Unsupported WAV encoding.\nSupported: PCM 8/16/24/32-bit and 32-bit float, mono or stereo."
              : rc == -4 ? "That WAV contains no usable audio."
              : "That file does not parse as a WAV.");
        return;
    }
    SetCursor(LoadCursorA(NULL, (LPCSTR)IDC_WAIT));
    int w1 = slot_write_sample(&g_disk, s, wi->sample);       /* audio first */
    int w2 = w1 == 0 ? slot_write_header(&g_disk, s, wi->hdr) : -1; /* header last */
    SetCursor(LoadCursorA(NULL, (LPCSTR)IDC_ARROW));
    if (w1 != 0 || w2 != 0) { free(wi); msg_err("Import failed while writing slot sectors."); return; }
    g_modified = 1;
    refresh_list();
    set_status(wi->msg);
    free(wi);
}

static void do_clear(void)
{
    SlotInfo si;
    int s = need_slot(&si);
    if (s < 0) return;
    if (si.kind == SLOT_EMPTY) { set_status("Slot is already empty."); return; }
    char q[96];
    wsprintfA(q, "Clear slot %d?\n(The slot header is blanked; the program is gone.)", s);
    if (MessageBoxA(g_hwnd, q, APP_NAME, MB_YESNO | MB_ICONWARNING) != IDYES) return;
    if (g_playing_slot == s) stop_play();
    if (slot_clear(&g_disk, s) != 0) { msg_err("Could not clear the slot."); return; }
    g_modified = 1;
    refresh_list();
    char st[64];
    wsprintfA(st, "Slot %d cleared.", s);
    set_status(st);
}

/* ---------------------------------------------------------------- window */

static HWND mkbtn(HWND parent, const char *text, int id, int x, int y, int w, int h)
{
    HWND b = CreateWindowExA(0, "BUTTON", text,
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
        x, y, w, h, parent, (HMENU)(INT_PTR)id, GetModuleHandleA(NULL), NULL);
    SendMessageA(b, WM_SETFONT, (WPARAM)GetStockObject(DEFAULT_GUI_FONT), TRUE);
    return b;
}

static void build_ui(HWND hwnd)
{
    INITCOMMONCONTROLSEX icc = { sizeof icc, ICC_LISTVIEW_CLASSES };
    InitCommonControlsEx(&icc);

    g_btn[0] = mkbtn(hwnd, "Open Disk\x85",    ID_OPEN,   12,  10, 110, 28);
    g_btn[1] = mkbtn(hwnd, "New Disk",         ID_NEW,    130, 10, 110, 28);
    g_btn[2] = mkbtn(hwnd, "Save Disk As\x85", ID_SAVEAS, 248, 10, 110, 28);

    g_list = CreateWindowExA(WS_EX_CLIENTEDGE, WC_LISTVIEWA, "",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS,
        12, 48, 636, 236, hwnd, (HMENU)ID_LIST, GetModuleHandleA(NULL), NULL);
    SendMessageA(g_list, WM_SETFONT, (WPARAM)GetStockObject(DEFAULT_GUI_FONT), TRUE);
    SendMessageA(g_list, LVM_SETEXTENDEDLISTVIEWSTYLE, 0,
                 LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES);

    static const struct { const char *name; int w; } cols[5] = {
        {"Slot", 48}, {"Contents", 200}, {"Rate", 120}, {"Loop", 70}, {"Length", 90}
    };
    for (int c = 0; c < 5; c++) {
        LVCOLUMNA lc;
        memset(&lc, 0, sizeof lc);
        lc.mask = LVCF_TEXT | LVCF_WIDTH;
        lc.pszText = (char *)cols[c].name;
        lc.cx = cols[c].w;
        SendMessageA(g_list, LVM_INSERTCOLUMNA, (WPARAM)c, (LPARAM)&lc);
    }
    for (int s = 0; s < SLOT_COUNT; s++) {
        char num[8];
        wsprintfA(num, "%d", s);
        LVITEMA it;
        memset(&it, 0, sizeof it);
        it.mask = LVIF_TEXT;
        it.iItem = s;
        it.pszText = num;
        SendMessageA(g_list, LVM_INSERTITEMA, 0, (LPARAM)&it);
    }

    g_btn[3] = mkbtn(hwnd, "Play",            ID_PLAY,   12,  294, 68,  28);
    g_btn[4] = mkbtn(hwnd, "Extract WAV\x85", ID_WAV,    88,  294, 112, 28);
    g_btn[5] = mkbtn(hwnd, "Export .oro\x85", ID_EXPORT, 208, 294, 105, 28);
    g_btn[6] = mkbtn(hwnd, "Import .oro\x85", ID_IMPORT, 321, 294, 105, 28);
    g_btn[8] = mkbtn(hwnd, "Import WAV\x85", ID_IMPWAV, 434, 294, 112, 28);
    g_btn[7] = mkbtn(hwnd, "Clear Slot",      ID_CLEAR,  554, 294, 82,  28);

    g_status = CreateWindowExA(0, "STATIC",
        "Open an Orovela disk image, or create a new disk and import .oro programs.",
        WS_CHILD | WS_VISIBLE | SS_LEFT, 12, 332, 636, 20,
        hwnd, (HMENU)ID_STATUS, GetModuleHandleA(NULL), NULL);
    SendMessageA(g_status, WM_SETFONT, (WPARAM)GetStockObject(DEFAULT_GUI_FONT), TRUE);

    refresh_list();
}

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE:
        g_hwnd = hwnd;
        build_ui(hwnd);
        return 0;
    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case ID_OPEN:   do_open();   return 0;
        case ID_NEW:    do_new();    return 0;
        case ID_SAVEAS: do_saveas(); return 0;
        case ID_PLAY:   do_play();   return 0;
        case ID_WAV:    do_wav();    return 0;
        case ID_EXPORT: do_export(); return 0;
        case ID_IMPORT: do_import(); return 0;
        case ID_IMPWAV: do_impwav(); return 0;
        case ID_CLEAR:  do_clear();  return 0;
        }
        return 0;
    case WM_CLOSE:
        if (!confirm_discard()) return 0;
        stop_play();
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR cmdline, int show)
{
    (void)hPrev; (void)cmdline;
    WNDCLASSA wc;
    memset(&wc, 0, sizeof wc);
    wc.lpfnWndProc = wndproc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    wc.hIcon = LoadIconA(NULL, (LPCSTR)IDI_APPLICATION);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = "OrovelaSM";
    RegisterClassA(&wc);

    RECT r = {0, 0, 660, 360};
    AdjustWindowRect(&r, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, FALSE);
    HWND hwnd = CreateWindowExA(0, "OrovelaSM", APP_NAME " " APP_VERSION,
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left, r.bottom - r.top,
        NULL, NULL, hInst, NULL);
    ShowWindow(hwnd, show);
    UpdateWindow(hwnd);
    set_title();

    MSG m;
    while (GetMessageA(&m, NULL, 0, 0) > 0) {
        if (!IsDialogMessageA(hwnd, &m)) {
            TranslateMessage(&m);
            DispatchMessageA(&m);
        }
    }
    return 0;
}
