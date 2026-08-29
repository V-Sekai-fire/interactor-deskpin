#include <windows.h>
#include <erl_nif.h>

static ERL_NIF_TERM atom_ok, atom_error, atom_hotkey, atom_nil, atom_true, atom_false;

typedef struct {
  ErlNifTid tid;
  DWORD thread_id;
  ErlNifPid owner;
  UINT mods;
  UINT vk;
  int running;
} hotkey_state;

static hotkey_state g_hotkey = {0};

static ERL_NIF_TERM utf8_binary(ErlNifEnv *env, const wchar_t *w)
{
  int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
  ERL_NIF_TERM term;
  unsigned char *buf;
  if (need <= 1) {
    enif_make_new_binary(env, 0, &term);
    return term;
  }
  buf = enif_make_new_binary(env, (size_t)(need - 1), &term);
  WideCharToMultiByte(CP_UTF8, 0, w, -1, (char *)buf, need, NULL, NULL);
  return term;
}

static HWND term_to_hwnd(ErlNifEnv *env, ERL_NIF_TERM t)
{
  ErlNifUInt64 v = 0;
  if (!enif_get_uint64(env, t, &v)) return NULL;
  return (HWND)(ULONG_PTR)v;
}

static ERL_NIF_TERM hwnd_to_term(ErlNifEnv *env, HWND h)
{
  return enif_make_uint64(env, (ErlNifUInt64)(ULONG_PTR)h);
}

static BOOL CALLBACK find_worker(HWND hwnd, LPARAM lp)
{
  wchar_t cls[64];
  HWND *out = (HWND *)lp;
  if (GetClassNameW(hwnd, cls, 64) && wcscmp(cls, L"WorkerW") == 0) {
    if (FindWindowExW(hwnd, NULL, L"SHELLDLL_DefView", NULL) == NULL) *out = hwnd;
  }
  return TRUE;
}

/* The wallpaper layer is the WorkerW with no SHELLDLL_DefView child; 0x052C
   asks Progman to split the desktop so that layer exists. */
static HWND desktop_layer(void)
{
  HWND progman = FindWindowW(L"Progman", NULL);
  HWND worker = NULL;
  DWORD_PTR res = 0;

  if (progman) {
    SendMessageTimeoutW(progman, 0x052C, 0, 0, SMTO_NORMAL, 1000, &res);
    SendMessageTimeoutW(progman, 0x052C, 0x0000000D, 0x00000001, SMTO_NORMAL, 1000, &res);
  }
  EnumWindows(find_worker, (LPARAM)&worker);
  if (!worker && progman) worker = FindWindowExW(progman, NULL, L"WorkerW", NULL);
  if (!worker) worker = progman;
  return worker;
}

static ERL_NIF_TERM nif_desktop_layer(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  HWND w = desktop_layer();
  if (!w) return enif_make_tuple2(env, atom_error, enif_make_atom(env, "no_workerw"));
  return enif_make_tuple2(env, atom_ok, hwnd_to_term(env, w));
}

static ERL_NIF_TERM nif_foreground(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  HWND h = GetForegroundWindow();
  if (!h) return atom_nil;
  return hwnd_to_term(env, h);
}

typedef struct {
  HWND *items;
  int count;
  int cap;
} window_list;

static BOOL CALLBACK collect(HWND hwnd, LPARAM lp)
{
  window_list *list = (window_list *)lp;
  if (!IsWindowVisible(hwnd) || GetWindowTextLengthW(hwnd) == 0) return TRUE;
  if (list->count == list->cap) {
    int cap = list->cap * 2;
    HWND *grown = (HWND *)enif_realloc(list->items, (size_t)cap * sizeof(HWND));
    if (!grown) return FALSE;
    list->items = grown;
    list->cap = cap;
  }
  list->items[list->count++] = hwnd;
  return TRUE;
}

static ERL_NIF_TERM nif_windows(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  window_list list;
  ERL_NIF_TERM acc = enif_make_list(env, 0);
  int i;

  list.cap = 64;
  list.count = 0;
  list.items = (HWND *)enif_alloc((size_t)list.cap * sizeof(HWND));
  if (!list.items) return enif_make_badarg(env);
  EnumWindows(collect, (LPARAM)&list);

  for (i = list.count - 1; i >= 0; i--) {
    HWND h = list.items[i];
    wchar_t title[512], cls[128];
    DWORD pid = 0;
    ERL_NIF_TERM map = enif_make_new_map(env);

    title[0] = 0;
    cls[0] = 0;
    GetWindowTextW(h, title, 512);
    GetClassNameW(h, cls, 128);
    GetWindowThreadProcessId(h, &pid);

    enif_make_map_put(env, map, enif_make_atom(env, "hwnd"), hwnd_to_term(env, h), &map);
    enif_make_map_put(env, map, enif_make_atom(env, "title"), utf8_binary(env, title), &map);
    enif_make_map_put(env, map, enif_make_atom(env, "class"), utf8_binary(env, cls), &map);
    enif_make_map_put(env, map, enif_make_atom(env, "os_pid"), enif_make_uint(env, pid), &map);
    acc = enif_make_list_cell(env, map, acc);
  }
  enif_free(list.items);
  return acc;
}

static ERL_NIF_TERM nif_info(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  HWND h = term_to_hwnd(env, argv[0]);
  wchar_t title[512], cls[128];
  DWORD pid = 0;
  ERL_NIF_TERM map;

  if (!h || !IsWindow(h)) return atom_nil;
  title[0] = 0;
  cls[0] = 0;
  GetWindowTextW(h, title, 512);
  GetClassNameW(h, cls, 128);
  GetWindowThreadProcessId(h, &pid);

  map = enif_make_new_map(env);
  enif_make_map_put(env, map, enif_make_atom(env, "hwnd"), hwnd_to_term(env, h), &map);
  enif_make_map_put(env, map, enif_make_atom(env, "title"), utf8_binary(env, title), &map);
  enif_make_map_put(env, map, enif_make_atom(env, "class"), utf8_binary(env, cls), &map);
  enif_make_map_put(env, map, enif_make_atom(env, "os_pid"), enif_make_uint(env, pid), &map);
  return map;
}

static ERL_NIF_TERM nif_pin(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  HWND target = term_to_hwnd(env, argv[0]);
  HWND layer;
  int cx, cy;

  if (!target || !IsWindow(target))
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "no_such_window"));
  layer = desktop_layer();
  if (!layer) return enif_make_tuple2(env, atom_error, enif_make_atom(env, "no_workerw"));

  SetLastError(0);
  if (!SetParent(target, layer) && GetLastError() != 0)
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "setparent_failed"));

  cx = GetSystemMetrics(SM_CXSCREEN);
  cy = GetSystemMetrics(SM_CYSCREEN);
  SetWindowPos(target, NULL, 0, 0, cx, cy, SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  ShowWindow(target, SW_SHOW);
  return enif_make_tuple2(env, atom_ok, hwnd_to_term(env, layer));
}

static ERL_NIF_TERM nif_unpin(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  HWND target = term_to_hwnd(env, argv[0]);
  if (!target || !IsWindow(target))
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "no_such_window"));
  SetParent(target, NULL);
  ShowWindow(target, SW_RESTORE);
  SetWindowPos(target, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  return atom_ok;
}

static ERL_NIF_TERM nif_parent(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  HWND target = term_to_hwnd(env, argv[0]);
  HWND parent;
  if (!target || !IsWindow(target)) return atom_nil;
  parent = GetAncestor(target, GA_PARENT);
  if (!parent || parent == GetDesktopWindow()) return atom_nil;
  return hwnd_to_term(env, parent);
}

static ERL_NIF_TERM nif_alive(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  HWND target = term_to_hwnd(env, argv[0]);
  return (target && IsWindow(target)) ? atom_true : atom_false;
}

static void *hotkey_loop(void *arg)
{
  hotkey_state *st = (hotkey_state *)arg;
  MSG msg;
  ErlNifEnv *env;
  BOOL ok;

  st->thread_id = GetCurrentThreadId();
  PeekMessageW(&msg, NULL, WM_USER, WM_USER, PM_NOREMOVE);
  ok = RegisterHotKey(NULL, 1, st->mods | MOD_NOREPEAT, st->vk);

  env = enif_alloc_env();
  enif_send(NULL, &st->owner, env,
            enif_make_tuple2(env, enif_make_atom(env, "hotkey_ready"),
                             ok ? atom_true : atom_false));
  enif_clear_env(env);

  while (GetMessageW(&msg, NULL, 0, 0) > 0) {
    if (msg.message == WM_HOTKEY) {
      enif_send(NULL, &st->owner, env, atom_hotkey);
      enif_clear_env(env);
    }
  }

  if (ok) UnregisterHotKey(NULL, 1);
  enif_free_env(env);
  st->running = 0;
  return NULL;
}

static ERL_NIF_TERM nif_hotkey_start(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  unsigned int mods, vk;
  if (g_hotkey.running)
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "already_running"));
  if (!enif_get_uint(env, argv[0], &mods) || !enif_get_uint(env, argv[1], &vk))
    return enif_make_badarg(env);
  if (!enif_self(env, &g_hotkey.owner)) return enif_make_badarg(env);

  g_hotkey.mods = mods;
  g_hotkey.vk = vk;
  g_hotkey.running = 1;
  if (enif_thread_create("deskpin_hotkey", &g_hotkey.tid, hotkey_loop, &g_hotkey, NULL) != 0) {
    g_hotkey.running = 0;
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "thread_failed"));
  }
  return atom_ok;
}

static ERL_NIF_TERM nif_hotkey_stop(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  if (!g_hotkey.running) return atom_ok;
  PostThreadMessageW(g_hotkey.thread_id, WM_QUIT, 0, 0);
  enif_thread_join(g_hotkey.tid, NULL);
  return atom_ok;
}

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info)
{
  atom_ok = enif_make_atom(env, "ok");
  atom_error = enif_make_atom(env, "error");
  atom_hotkey = enif_make_atom(env, "hotkey");
  atom_nil = enif_make_atom(env, "nil");
  atom_true = enif_make_atom(env, "true");
  atom_false = enif_make_atom(env, "false");
  return 0;
}

static ErlNifFunc funcs[] = {
  {"foreground", 0, nif_foreground, 0},
  {"windows", 0, nif_windows, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"info", 1, nif_info, 0},
  {"desktop_layer", 0, nif_desktop_layer, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"pin", 1, nif_pin, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"unpin", 1, nif_unpin, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"parent", 1, nif_parent, 0},
  {"alive", 1, nif_alive, 0},
  {"hotkey_start", 2, nif_hotkey_start, 0},
  {"hotkey_stop", 0, nif_hotkey_stop, ERL_NIF_DIRTY_JOB_IO_BOUND}
};

ERL_NIF_INIT(Elixir.Deskpin.Win32, funcs, load, NULL, NULL, NULL)
