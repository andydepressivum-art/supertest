;==================================================================
; defs.inc - constants, struct layouts and Win32 API declarations
;            for petri.asm (x86-64 NASM, output format win64).
;==================================================================

;------------------------- kernel32 --------------------------------
extern GetModuleHandleW, ExitProcess, GetTickCount
extern CreateThread, WaitForSingleObject, SetEvent, CloseHandle
extern GetSystemInfo, TlsAlloc, TlsGetValue, TlsSetValue
extern CreateEventA

;------------------------- user32 ----------------------------------
extern RegisterClassExW, CreateWindowExW, DefWindowProcW
extern ShowWindow, UpdateWindow, GetMessageW, TranslateMessage
extern DispatchMessageW, PostQuitMessage, BeginPaint, EndPaint
extern ValidateRect, SetTimer, KillTimer, MessageBoxA
extern DrawTextA, wsprintfA, LoadCursorW, LoadIconW
extern InvalidateRect, GetClientRect

;-------------------------- gdi32 ----------------------------------
extern CreateCompatibleDC, CreateDIBSection, SelectObject, DeleteDC
extern BitBlt, GetStockObject, CreateFontA, ExtTextOutA, SetBkMode

;======================== WINDOW CONSTANTS =========================
WM_DESTROY      equ 0x0002
WM_PAINT        equ 0x000F
WM_CLOSE        equ 0x0010
WM_KEYDOWN      equ 0x0100
WM_TIMER        equ 0x0113
WM_SIZE         equ 0x0005
WM_ERASEBKGND   equ 0x0014

WS_OVERLAPPEDWINDOW equ 0x00CF0000
CW_USEDEFAULT   equ -1                ; 0x80000000 as a signed dword
SW_SHOWNORMAL   equ 1
CS_HREDRAW      equ 0x0002
CS_VREDRAW      equ 0x0001
WS_VISIBLE      equ 0x10000000

VK_SPACE        equ 0x20
VK_ESCAPE       equ 0x1B
VK_ADD          equ 0x6B
VK_SUBTRACT     equ 0x6D
VK_OEM_PLUS     equ 0xBB              ; '=' key (shifted '+')
VK_OEM_MINUS    equ 0xBD              ; '-' key
VK_R            equ 0x52
VK_G            equ 0x47
VK_P            equ 0x50

INFINITE        equ 0xFFFFFFFF

DT_LEFT         equ 0x0000
FW_NORMAL       equ 400
DEFAULT_CHARSET equ 1
OUT_TT_PRECIS   equ 3
CLIP_DEFAULT_PRECIS equ 0
ANTIALIASED_QUALITY equ 4
DEFAULT_PITCH   equ 0
FF_DONTCARE     equ 0

SRCCOPY         equ 0x00CC0020
DIB_RGB_COLORS  equ 0
BLACK_BRUSH     equ 4
NULL_PEN        equ 8
COLOR_WINDOW    equ 5
IDC_ARROW       equ 32512
IDI_APPLICATION equ 32512

MB_OK           equ 0
MB_ICONERROR    equ 0x10

; WNDCLASSEXW layout (x64)
struc WNDCLASSEXW nofill
{
    .cbSize        resd 1
    .style         resd 1
    .lpfnWndProc   resq 1
    .cbClsExtra    resd 1
    .cbWndExtra    resd 1
    .hInstance     resq 1
    .hIcon         resq 1
    .hCursor       resq 1
    .hbrBackground resq 1
    .lpszMenuName  resq 1
    .lpszClassName resq 1
    .hIconSm       resq 1
}
WNDCLASSEX_SIZE equ 80                ; sizeof(WNDCLASSEXW) on x64

; PAINTSTRUCT (x64): HDC(8) fErase(4) RECT(16) fRestore(8)
; fIncUpdate(8) rgbReserved(32) = 80 bytes total
PS_SIZE     equ 80
PS_HDC      equ 0                   ; hdc at offset 0

; BITMAPINFOHEADER field offsets
BMIH_SIZE   equ 0                   ; biSize
BMIH_W      equ 4                   ; biWidth
BMIH_H      equ 8                   ; biHeight (positive => bottom-up)
BMIH_PLANES equ 12                  ; biPlanes
BMIH_BITCNT equ 14                  ; biBitCount
BMIH_COMP   equ 16                  ; biCompression
BMIH_SIZEIM equ 20                  ; biSizeImage
BITMAPINFO_SIZE equ 44              ; header(40) + one unused RGB quad

; SYSTEM_INFO (x64) actual header order:
;   union {dwOemId; {ProcessorArchitecture,Level,Revision}} (8 bytes)
;   dwPageSize (4) @+8 ; wProcessorLevel (2) @+12 ;
;   wProcessorRevision (2) @+14 ; dwNumberOfProcessors (4) @+16.
SI_CPU_COUNT equ 16                 ; dwNumberOfProcessors

;======================== SIMULATION CONSTANTS =====================
; The dish is a fixed rectangle centered inside whatever client area
; the window has (resizable). Default client size below.
WORLD_W   equ 960                 ; dish size in pixels (fixed)
WORLD_H   equ 640
WIN_W     equ WORLD_W + 32        ; default client width
WIN_H     equ WORLD_H + 160       ; default client height (dish + HUD)
OFFY      equ 16                  ; top margin of the dish in client

FP        equ 256                 ; 16.8 fixed-point scale everywhere
MAX_ORG   equ 4096                ; hard population cap
MAX_FOOD  equ 8192                ; hard food-particle cap

; Organism struct: 17 qwords = 136 bytes.
ORG_STRIDE equ 136
O_X        equ 0                  ; position, fp px
O_Y        equ 8                  ; position, fp px
O_DIR      equ 16                 ; heading, fp degrees [0,360*FP)
O_SPEED    equ 24                 ; trait: px/tick, fp (64..1024)
O_ENERGY   equ 32                 ; current energy, fp units
O_MAXENR   equ 40                 ; trait: energy cap, fp units
O_AGE      equ 48                 ; ticks alive
O_MAXAGE   equ 56                 ; trait: lifespan (ticks)
O_METAB    equ 64                 ; trait: metabolism index (5..100)
O_SENSE    equ 72                 ; trait: sense radius px (16..240)
O_REPRO    equ 80                 ; trait: repro threshold, fp
O_TYPE     equ 88                 ; 0 gatherer / 1 predator
O_GEN      equ 96                 ; generation number
O_MUTF     equ 104                ; mutation strength percent (20..300)
O_DIET     equ 112                ; carnivory tendency 0..1000
O_TIDX     equ 120                ; target index (-1 none), phase-1 scratch
O_FLAGS    equ 128                ; bit0 = dead this tick

ORG_DEAD equ 1

; Food record: two int32 pixel coordinates padded to 16 bytes
FOOD_STRIDE equ 16
F_X         equ 0
F_Y         equ 4

;------------------- simulation balance constants ------------------
; Per-tick energy cost (fp units):
;   cost = BASE_COST + speed^2*SPEED_K/FP + metab*MET_K/FP
;          + tempstress + tox*TOX_K/FP
BASE_COST    equ 2
SPEED_K      equ 14
MET_K        equ 10
TEMP_K       equ 4                  ; stress = dev^2*TEMP_K >> 16
TOX_K        equ 3
TURN_FP      equ 12*FP              ; max heading change per tick
BITE_R2      equ 49                 ; predator bite range squared (7 px)
EAT_R2       equ 36                 ; food pickup range squared (6 px)
PREY_GAIN    equ 3000               ; energy from eating prey
FOOD_VALUE   equ 1400               ; energy per food particle
BIRTH_MIN_EN equ 4200               ; parent must keep at least this
BIRTH_TAX    equ 600                ; extra energy cost of birth
FOOD_TARGET  equ 1600               ; equilibrium food population
REGEN_NUM    equ 24                 ; food regen: gap*24/1024 per tick
SPEED_MUT_SCALE equ 8               ; speed mutation quantum (fp)
INIT_SUN     equ 800

; Initial world
INIT_GATHERERS equ 300
INIT_PREDATORS equ 20
INIT_FOOD      equ 1000

; Worker pool bounds (main thread excluded)
WORKER_MIN equ 1
WORKER_MAX equ 15

; Rendering / timing
TIMER_ID equ 1
TICK_MS  equ 33                     ; ~30 render frames per second
SPEED_STEPS equ 5                   ; selectable sim speeds (steps/frame)
