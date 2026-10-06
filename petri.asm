;=====================================================================
; petri.asm - "Petri Dish": graphical evolution / microbiology sim
;             x86-64 NASM (win64 object format), Windows 10/11.
;
; Pure Win32 + GDI. No CRT, no external frameworks or packages.
;
; BUILD (Microsoft toolchain, e.g. "Developer Command Prompt"):
;   nasm -f win64 petri.asm -o petri.obj
;   link /SUBSYSTEM:WINDOWS /OUT:petri.exe petri.obj user32.lib gdi32.lib kernel32.lib
;
; BUILD (mingw-w64 alternative):
;   nasm -f win64 petri.asm -o petri.obj
;   x86_64-w64-mingw32-gcc -nostartfiles -s -mwindows -o petri.exe petri.obj ^
;       -lkernel32 -luser32 -lgdi32
;
;---------------------------------------------------------------------
; THREADING MODEL
;   Main thread : message loop. WM_TIMER (~30 Hz) runs K simulation
;                 ticks (K = speed setting; rendering stays at ~30 fps
;                 while the biology speeds up), then InvalidateRect.
;                 WM_PAINT blits the off-screen DIB back-buffer to the
;                 window. The main thread also executes PHASE 2 of
;                 every tick serially: predation, feeding, births,
;                 deaths, environment drift - simple and race-free.
;   Worker pool : N = logical CPUs - 1 threads (clamped to 1..15).
;                 Each blocks on its own auto-reset event go[i], runs
;                 PHASE 1 over its private contiguous organism range
;                 [lo[i],hi[i]) (sense -> steer -> move -> spend
;                 energy -> select target), then signals done[i].
;                 The go/done event pairs form a barrier; no locks are
;                 needed because workers write only their own
;                 organisms' records and food/env arrays are read-only
;                 during phase 1.
;
; MICROSOFT x64 CALLING CONVENTION (obeyed at every API call site):
;   args 1..4 -> rcx,rdx,r8,r9 ; args 5+ pushed right-to-left ;
;   caller reserves 32 bytes of shadow space ; RSP must be 16-byte
;   aligned immediately before CALL. Callee-saved: rbx,rbp,rsi,rdi,
;   r12-r15. Internal procedures follow the same rules so they can
;   call APIs directly.
;
; NUMBERS
;   Position/speed/energy use 16.8 fixed point (FP=256 counts = 1 px
;   or 1 energy unit). Heading is fixed-point DEGREES in [0,360*FP);
;   movement uses the integer table dir_sin[] (Q8.8 sine sampled every
;   0.5 degrees, see sintab.inc). All hot-loop math is integer.
;
; PRNG
;   xorshift64* (public domain, Vigna). One stream per thread: each
;   thread stores a pointer to its own state block in a TlsAlloc slot,
;   so generating random numbers requires zero synchronization.
;=====================================================================

default rel
bits 64

%include "defs.inc"                  ; constants, struct layouts, externs
%include "sintab.inc"                ; dir_sin lookup table

;========================== CODE SECTION =============================
section .text align=16

;=====================================================================
;                          P R N G
;=====================================================================
rand_next:                          ; -> rax ; clobbers rax,rcx,rdx only
    mov   ecx, [TLS_INDEX]
    call  TlsGetValue               ; returns our state-block pointer
    mov   rdx, [rax]
    mov   rcx, rdx
    shr   rcx, 12
    xor   rdx, rcx                  ; x ^= x >> 12
    mov   rcx, rdx
    shl   rcx, 25
    xor   rdx, rcx                  ; x ^= x << 25
    mov   rcx, rdx
    shr   rcx, 27
    xor   rdx, rcx                  ; x ^= x >> 27
    imul  rdx, rdx, 0x2545F4914F6CDD1D
    mov   [rax], rdx                ; save new state
    mov   rax, rdx
    ret

rand_lt:                            ; rcx = bound (>0) -> rax in [0,n)
    sub   rsp, 0x28
    mov   [rsp+0x20], rcx
    call  rand_next
    mov   rcx, [rsp+0x20]
    xor   edx, edx
    div   rcx                       ; unsigned remainder
    mov   rax, rdx
    add   rsp, 0x28
    ret

rng_set_state:                      ; rcx = state block ptr, rdx = seed
    test  rdx, rdx
    jnz   1f
    mov   rdx, 0x123456789ABCDEF0   ; never store a zero state
1:  mov   [rcx], rdx
    mov   ecx, [TLS_INDEX]
    jmp   TlsSetValue

;=====================================================================
;                     W O R L D   S E T U P
;=====================================================================
spawn_organism:                     ; rcx = type (0 gatherer/1 predator)
    push  rbx
    sub   rsp, 0x20
    mov   rbx, rcx
    cmp   dword [g_org_count], MAX_ORG
    jae   .so_ret
    mov   eax, [g_org_count]
    imul  rax, rax, ORG_STRIDE
    lea   r10, [orgs]
    add   r10, rax
    mov   rcx, WORLD_W*FP
    call  rand_lt
    mov   [r10+O_X], rax
    mov   rcx, WORLD_H*FP
    call  rand_lt
    mov   [r10+O_Y], rax
    mov   rcx, 360*FP
    call  rand_lt
    mov   [r10+O_DIR], rax
    test  ebx, ebx
    jnz   .pred_f
    ; ---- gatherer founder ranges ----
    mov   rcx, 257                  ; speed 128..384 fp (.5-1.5 px/tick)
    call  rand_lt
    add   rax, 128
    mov   [r10+O_SPEED], rax
    mov   rcx, 41                   ; metabolism 20..60
    call  rand_lt
    add   rax, 20
    mov   [r10+O_METAB], rax
    mov   rcx, 101                  ; sense radius 40..140 px
    call  rand_lt
    add   rax, 40
    mov   [r10+O_SENSE], rax
    mov   rcx, 251                  ; diet tendency 0..250 (herbivory)
    call  rand_lt
    mov   [r10+O_DIET], rax
    jmp   .common_f
.pred_f:
    ; ---- predator founder ranges ----
    mov   rcx, 385                  ; speed 256..640 fp (1-2.5 px/tick)
    call  rand_lt
    add   rax, 256
    mov   [r10+O_SPEED], rax
    mov   rcx, 51                   ; metabolism 40..90
    call  rand_lt
    add   rax, 40
    mov   [r10+O_METAB], rax
    mov   rcx, 121                  ; sense radius 80..200 px
    call  rand_lt
    add   rax, 80
    mov   [r10+O_SENSE], rax
    mov   rcx, 301                  ; diet 600..900 (carnivory)
    call  rand_lt
    add   rax, 600
    mov   [r10+O_DIET], rax
.common_f:
    mov   [r10+O_TYPE], rbx
    mov   qword [r10+O_MAXENR], 9000
    mov   qword [r10+O_ENERGY], 6000
    mov   qword [r10+O_AGE], 0
    mov   rcx, 2001                 ; lifespan 1200..3200 ticks
    call  rand_lt
    add   rax, 1200
    mov   [r10+O_MAXAGE], rax
    mov   rcx, 2001                 ; repro threshold 7000..9000 fp
    call  rand_lt
    add   rax, 7000
    mov   [r10+O_REPRO], rax
    mov   qword [r10+O_GEN], 0
    mov   rcx, 81                   ; mutation factor 20..100 percent
    call  rand_lt
    add   rax, 20
    mov   [r10+O_MUTF], rax
    mov   qword [r10+O_FLAGS], 0
    mov   qword [r10+O_TIDX], -1
    inc   dword [g_org_count]
.so_ret:
    add   rsp, 0x20
    pop   rbx
    ret

spawn_food_one:                     ; append one food particle
    cmp   dword [g_food_count], MAX_FOOD
    jae   .sf_ret
    mov   eax, [g_food_count]
    imul  eax, eax, FOOD_STRIDE
    lea   r10, [food]
    add   r10, rax
    mov   rcx, WORLD_W
    call  rand_lt
    mov   [r10+F_X], eax
    mov   rcx, WORLD_H
    call  rand_lt
    mov   [r10+F_Y], eax
    inc   dword [g_food_count]
.sf_ret:
    ret

sim_reset:                          ; wipe world, reseed founders
    push  rbx
    sub   rsp, 0x20
    mov   dword [g_org_count], 0
    mov   dword [g_food_count], 0
    mov   dword [g_tick], 0
    mov   dword [g_env_phase], 0
    mov   dword [g_tox], 0
    mov   dword [g_temp], 500
    mov   dword [g_sun], INIT_SUN
    mov   dword [g_max_gen], 0
    mov   dword [g_stat_births], 0
    mov   dword [g_stat_deaths], 0
    mov   dword [g_stat_eaten], 0
    mov   dword [g_stat_kills], 0
    mov   rbx, INIT_GATHERERS
.rs1:
    xor   ecx, ecx
    call  spawn_organism
    dec   rbx
    jnz   .rs1
    mov   rbx, INIT_PREDATORS
.rs2:
    mov   ecx, 1
    call  spawn_organism
    dec   rbx
    jnz   .rs2
    mov   rbx, INIT_FOOD
.rs3:
    call  spawn_food_one
    dec   rbx
    jnz   .rs3
    add   rsp, 0x20
    pop   rbx
    ret

;=====================================================================
;                S I M   T I C K   (barrier orchestrator)
;=====================================================================
sim_tick:
    push  rbx
    push  rbp
    push  rsi
    push  rdi
    push  r12
    push  r13
    push  r14
    push  r15
    sub   rsp, 0x20

    inc   dword [g_tick]

    ; chunk = ceil(ceil(N/W)/4)*4 (multiple of 4 keeps ranges tidy)
    mov   eax, [g_org_count]
    mov   ecx, [g_worker_count]
    xor   edx, edx
    div   ecx
    test  edx, edx
    jz    1f
    inc   eax                       ; ceil(N/W)
1:  add   eax, 3
    and   eax, ~3
    mov   r12d, eax                 ; chunk size
    xor   ebx, ebx                  ; worker index
    xor   ebp, ebp                  ; running lo
.assign:
    mov   esi, ebp
    add   esi, r12d
    cmp   esi, [g_org_count]
    jbe   2f
    mov   esi, [g_org_count]        ; hi = min(lo+chunk, N)
2:  mov   [g_w_lo + rbx*4], ebp
    mov   [g_w_hi + rbx*4], esi
    mov   ebp, esi
    inc   rbx
    cmp   ebx, [g_worker_count]
    jb    .assign
    ; wake ALL workers (empty ranges notify immediately, so the
    ; barrier wait count always matches the number of events created)
    xor   ebx, ebx
.wake:
    mov   rcx, [g_ev_go + rbx*8]
    call  SetEvent
    inc   ebx
    cmp   ebx, [g_worker_count]
    jb    .wake
    ; barrier: wait for every done[i]
    xor   ebx, ebx
.wait:
    mov   rcx, [g_ev_done + rbx*8]
    mov   rdx, INFINITE
    call  WaitForSingleObject
    inc   ebx
    cmp   ebx, [g_worker_count]
    jb    .wait

    call  phase2_update

    add   rsp, 0x20
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    pop   rdi
    pop   rsi
    pop   rbp
    pop   rbx
    ret

;=====================================================================
;                        W O R K E R   T H R E A D
;=====================================================================
worker_proc:                        ; rcx = &w_args[i] (qword = index)
    push  rbx
    push  rbp
    push  rsi
    push  rdi
    push  r12
    sub   rsp, 0x20

    mov   rbx, [rcx]                ; my index
    ; attach a private PRNG state block seeded uniquely per worker
    lea   r12, [w_rng_blocks]
    mov   rax, rbx
    shl   rax, 3
    add   r12, rax
    mov   rax, 0x9E3779B97F4A7C15
    imul  rax, rbx
    add   rax, [g_tick]
    xor   rax, r12
    mov   rdx, rax
    mov   rcx, r12
    call  rng_set_state
    mov   rbp, rbx                  ; persistent index

.wloop:
    mov   rcx, [g_ev_go + rbp*8]
    mov   rdx, INFINITE
    call  WaitForSingleObject
    mov   esi, [g_w_lo + rbp*4]     ; lo
    mov   edi, [g_w_hi + rbp*4]     ; hi
    cmp   esi, edi
    jge   .notify
    mov   r12, orgs                 ; walking pointer (callee-saved)
    imul  rax, rsi, ORG_STRIDE
    add   r12, rax
.nextorg:
    mov   rcx, r12
    call  update_organism_phase1
    add   r12, ORG_STRIDE
    inc   esi
    cmp   esi, edi
    jb    .nextorg
.notify:
    mov   rcx, [g_ev_done + rbp*8]
    call  SetEvent
    jmp   .wloop

;=====================================================================
;            P H A S E   1   -   o n e   o r g a n i s m
;=====================================================================
; rcx = pOrg. Sense target, steer toward it, move, bounce off walls,
; spend energy, age, mark death candidates. Writes ONLY this
; organism's record (plus its own PRNG state). Preserves all
; callee-saved registers.
;---------------------------------------------------------------------
update_organism_phase1:
    push  rbx
    push  r12
    push  r13
    push  r14
    push  r15
    sub   rsp, 0x20
    mov   rbx, rcx                  ; pOrg

    ; ---- heading wiggle +-10 degrees ----
    mov   rcx, 21*FP
    call  rand_lt
    sub   rax, 10*FP
    add   [rbx+O_DIR], rax
    call  wrap_dir

    ; ---- sense & select target ----
    mov   qword [rbx+O_TIDX], -1
    mov   eax, [rbx+O_TYPE]
    test  eax, eax
    jnz   .sense_pred

.sense_food:
    ; nearest food within O_SENSE px (compare squared distances)
    mov   eax, [rbx+O_SENSE]
    imul  r12d, eax, eax            ; r^2 in px^2
    mov   r13d, -1                  ; best index
    mov   r14d, 0x7FFFFFFF          ; best d^2
    mov   eax, [rbx+O_X]
    sar   eax, 8
    mov   r8d, eax                  ; myX px
    mov   eax, [rbx+O_Y]
    sar   eax, 8
    mov   r9d, eax                  ; myY px
    mov   r10, food
    xor   ecx, ecx
.foodloop:
    cmp   ecx, [g_food_count]
    jge   .food_end
    mov   eax, [r10+F_X]
    sub   eax, r8d
    imul  eax, eax
    mov   edx, [r10+F_Y]
    sub   edx, r9d
    imul  edx, edx
    add   eax, edx                  ; d^2
    cmp   eax, r12d
    ja    .food_next
    cmp   eax, r14d
    jae   .food_next
    mov   r14d, eax
    mov   r13d, ecx
.food_next:
    add   r10, FOOD_STRIDE
    inc   ecx
    jmp   .foodloop
.food_end:
    mov   [rbx+O_TIDX], r13
    test  r13d, r13d
    js    .move                     ; no target: keep wiggled heading
    mov   r10, food
    imul  r11, r13, FOOD_STRIDE
    add   r10, r11
    mov   ecx, [r10+F_X]
    sub   ecx, r8d                  ; dx px
    mov   edx, [r10+F_Y]
    sub   edx, r9d                  ; dy px
    call  steer_toward
    jmp   .move

.sense_pred:
    ; nearest living gatherer within O_SENSE px
    mov   eax, [rbx+O_SENSE]
    imul  r12d, eax, eax
    mov   r13d, -1
    mov   r14d, 0x7FFFFFFF
    mov   eax, [rbx+O_X]
    sar   eax, 8
    mov   r8d, eax
    mov   eax, [rbx+O_Y]
    sar   eax, 8
    mov   r9d, eax
    mov   r10, orgs
    xor   ecx, ecx
.predloop:
    cmp   ecx, [g_org_count]
    jge   .pred_end
    cmp   r10, rbx                  ; skip self
    je    .pred_next
    cmp   dword [r10+O_TYPE], 0     ; prey = gatherers only
    jne   .pred_next
    test  qword [r10+O_FLAGS], ORG_DEAD
    jnz   .pred_next
    mov   eax, [r10+O_X]
    sar   eax, 8
    sub   eax, r8d
    imul  eax, eax
    mov   edx, [r10+O_Y]
    sar   edx, 8
    sub   edx, r9d
    imul  edx, edx
    add   eax, edx
    cmp   eax, r12d
    ja    .pred_next
    cmp   eax, r14d
    jae   .pred_next
    mov   r14d, eax
    mov   r13d, ecx
.pred_next:
    add   r10, ORG_STRIDE
    inc   ecx
    jmp   .predloop
.pred_end:
    mov   [rbx+O_TIDX], r13
    test  r13d, r13d
    js    .move
    mov   r10, orgs
    imul  r11, r13, ORG_STRIDE
    add   r10, r11
    mov   ecx, [r10+O_X]
    sar   ecx, 8
    sub   ecx, r8d
    mov   edx, [r10+O_Y]
    sar   edx, 8
    sub   edx, r9d
    call  steer_toward

    ; ---- move along heading via sine table ----
.move:
    mov   eax, [rbx+O_DIR]
    shr   eax, 7                    ; 0.5-degree units (0..719)
    lea   eax, [rax+rax]            ; *2 bytes per table entry
    movzx r10d, word [dir_sin + rax]        ; sin(h)*256
    add   eax, 180*2                ; cos(h)=sin(h+90deg): +180 entries
    movzx r11d, word [dir_sin + rax]        ; cos(h)*256
    mov   rax, [rbx+O_SPEED]
    imul  rax, r11
    sar   rax, 8                    ; fp speed * Q8 cos -> fp delta
    add   [rbx+O_X], rax
    mov   rax, [rbx+O_SPEED]
    imul  rax, r10
    sar   rax, 8
    add   [rbx+O_Y], rax

    ; ---- wall bounce (clamp position, reverse heading) ----
    mov   rax, [rbx+O_X]
    cmp   rax, 0
    jl    .bx
    cmp   rax, WORLD_W*FP
    jle   .check_y
.bx:
    test  rax, rax
    jns   1f
    xor   eax, eax                  ; below 0 -> clamp to 0
    jmp   2f
1:  mov   rax, WORLD_W*FP - 1       ; beyond right edge -> clamp inside
2:  mov   [rbx+O_X], rax
    call  reverse_dir
.check_y:
    mov   rax, [rbx+O_Y]
    cmp   rax, 0
    jl    .by
    cmp   rax, WORLD_H*FP
    jle   .energy
.by:
    test  rax, rax
    jns   3f
    xor   eax, eax
    jmp   4f
3:  mov   rax, WORLD_H*FP - 1
4:  mov   [rbx+O_Y], rax
    call  reverse_dir

    ; ---- energy spend ----
.energy:
    ; cost = BASE_COST + speed^2*SPEED_K/FP + metab*MET_K/FP
    ;        + tempstress + tox*TOX_K/FP
    mov   rax, [rbx+O_SPEED]
    imul  rax, rax                  ; speed^2 (fp^2)
    imul  rax, rax, SPEED_K
    shr   rax, 8                    ; /FP -> fp units
    add   rax, BASE_COST
    mov   ecx, [rbx+O_METAB]
    imul  ecx, ecx, MET_K
    shr   ecx, 8
    add   rax, rcx
    ; temperature stress: dev = |temp-500| (permille, 0..250);
    ; stress = dev^2 * TEMP_K >> 16 (quadratic penalty)
    mov   ecx, [g_temp]
    sub   ecx, 500
    jns   5f
    neg   ecx
5:  imul  ecx, ecx
    imul  ecx, ecx, TEMP_K
    shr   ecx, 16
    add   rax, rcx
    ; toxicity drain (linear)
    mov   ecx, [g_tox]
    imul  ecx, ecx, TOX_K
    shr   ecx, 8
    add   rax, rcx
    sub   [rbx+O_ENERGY], rax

    ; ---- age & death marking ----
    inc   qword [rbx+O_AGE]
    mov   rax, [rbx+O_ENERGY]
    test  rax, rax
    jle   .mark_dead
    mov   rax, [rbx+O_AGE]
    cmp   rax, [rbx+O_MAXAGE]
    jg    .mark_dead
    jmp   .uo_end
.mark_dead:
    or    qword [rbx+O_FLAGS], ORG_DEAD
.uo_end:
    add   rsp, 0x20
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    pop   rbx
    ret

;---------------------------------------------------------------------
wrap_dir:                           ; normalize [rbx+O_DIR]; rax only
    mov   rax, [rbx+O_DIR]
.wd1:
    cmp   rax, 360*FP
    jb    .wd2
    sub   rax, 360*FP
    jmp   .wd1
.wd2:
    test  rax, rax
    jns   .wd3
    add   rax, 360*FP
    jmp   .wd2
.wd3:
    mov   [rbx+O_DIR], rax
    ret

reverse_dir:
    add   qword [rbx+O_DIR], 180*FP
    jmp   wrap_dir

;---------------------------------------------------------------------
; steer_toward: rcx = dx px, rdx = dy px, rbx = pOrg.
; Rotate the heading toward the target by TURN_FP using the sign of
; cross_z = cx*dy - cy*dx between current unit vector (cos,sin) and
; the delta vector. (Screen y grows downward; the same convention is
; used for movement below, so steering stays self-consistent.)
;---------------------------------------------------------------------
steer_toward:
    push  r10
    push  r11
    mov   eax, [rbx+O_DIR]
    shr   eax, 7
    lea   eax, [rax+rax]
    movzx r10d, word [dir_sin + rax]        ; cy = sin*256
    add   eax, 180*2
    movzx r11d, word [dir_sin + rax]        ; cx = cos*256
    mov   eax, r11d
    imul  eax, edx                  ; cx*dy
    imul  r10d, ecx                 ; cy*dx
    sub   eax, r10d                 ; cross_z
    test  eax, eax
    jle   .st_neg
    add   qword [rbx+O_DIR], TURN_FP
    pop   r11
    pop   r10
    jmp   wrap_dir
.st_neg:
    sub   qword [rbx+O_DIR], TURN_FP
    pop   r11
    pop   r10
    jmp   wrap_dir

;=====================================================================
;         P H A S E   2  -  s e r i a l   r e s o l u t i o n
;=====================================================================
; Predation -> feeding -> reproduction -> compaction -> environment.
; Array removals use swap-with-last (O(1)); scanning upward while
; shrinking from the tail keeps indices valid.
;---------------------------------------------------------------------
phase2_update:
    push  rbx
    push  rbp
    push  rsi
    push  rdi
    push  r12
    push  r13
    push  r14
    push  r15
    sub   rsp, 0x20

    ; ---------- 1. predation (sets DEAD flags only) ----------
    mov   eax, [g_org_count]
    imul  rax, rax, ORG_STRIDE
    lea   r13, [orgs + rax]         ; array end
    mov   r12, orgs
.killfw:
    cmp   r12, r13
    jae   .feedpass
    cmp   dword [r12+O_TYPE], 1
    jne   .killnext
    test  qword [r12+O_FLAGS], ORG_DEAD
    jnz   .killnext
    mov   rax, [r12+O_TIDX]
    test  rax, rax
    js    .killnext
    cmp   rax, [g_org_count]
    jge   .killnext
    imul  r14, rax, ORG_STRIDE
    add   r14, orgs                 ; pPrey
    test  qword [r14+O_FLAGS], ORG_DEAD
    jnz   .killnext
    cmp   dword [r14+O_TYPE], 0
    jne   .killnext
    ; bite range check: <= 7 px
    mov   eax, [r12+O_X]
    sar   eax, 8
    mov   ecx, [r14+O_X]
    sar   ecx, 8
    sub   eax, ecx
    imul  eax, eax
    mov   edx, [r12+O_Y]
    sar   edx, 8
    mov   ecx, [r14+O_Y]
    sar   ecx, 8
    sub   edx, ecx
    imul  edx, edx
    add   eax, edx
    cmp   eax, BITE_R2
    ja    .killnext
    ; successful attack: predator feeds, prey flagged dead
    mov   rax, [r12+O_ENERGY]
    add   rax, PREY_GAIN
    mov   r15, [r12+O_MAXENR]
    cmp   rax, r15
    cmova rax, r15
    mov   [r12+O_ENERGY], rax
    or    qword [r14+O_FLAGS], ORG_DEAD
    inc   dword [g_stat_kills]
.killnext:
    add   r12, ORG_STRIDE
    jmp   .killfw

    ; ---------- 2. feeding (removes food via swap-with-last) --------
.feedpass:
    mov   r12, orgs
.feedloop:
    mov   eax, [g_org_count]
    imul  rax, rax, ORG_STRIDE
    lea   r14, [orgs + rax]
    cmp   r12, r14
    jae   .birthpass
    cmp   dword [r12+O_TYPE], 0
    jne   .feednext
    test  qword [r12+O_FLAGS], ORG_DEAD
    jnz   .feednext
    mov   rax, [r12+O_TIDX]
    test  rax, rax
    js    .feednext
    cmp   rax, [g_food_count]
    jge   .feednext
    imul  r15, rax, FOOD_STRIDE
    add   r15, food                 ; pFood
    ; proximity re-check (<= 6 px): guards against stale targets
    ; (another gatherer may have eaten this slot earlier this pass)
    mov   eax, [r12+O_X]
    sar   eax, 8
    sub   eax, [r15+F_X]
    imul  eax, eax
    mov   edx, [r12+O_Y]
    sar   edx, 8
    sub   edx, [r15+F_Y]
    imul  edx, edx
    add   eax, edx
    cmp   eax, EAT_R2
    ja    .feednext
    ; eat it
    mov   rax, [r12+O_ENERGY]
    add   rax, FOOD_VALUE
    mov   r10, [r12+O_MAXENR]
    cmp   rax, r10
    cmova rax, r10
    mov   [r12+O_ENERGY], rax
    inc   dword [g_stat_eaten]
    ; remove eaten slot: copy last food into the hole, then shrink
    mov   esi, [g_food_count]
    dec   esi                       ; last index
    mov   edi, [r12+O_TIDX]         ; hole index
    cmp   esi, edi
    je    .fdrop
    imul  rax, rsi, FOOD_STRIDE
    imul  rdx, rdi, FOOD_STRIDE
    lea   r11, [food]
    mov   ecx, [r11+rax+F_X]
    mov   r8d, [r11+rax+F_Y]
    mov   [r11+rdx+F_X], ecx
    mov   [r11+rdx+F_Y], r8d
.fdrop:
    mov   eax, [g_food_count]
    dec   eax
    mov   [g_food_count], eax
    mov   qword [r12+O_TIDX], -1
    ; other gatherers that targeted the moved food now reference a
    ; duplicate position; harmless: eating re-checks distance first.
.feednext:
    add   r12, ORG_STRIDE
    jmp   .feedloop

    ; ---------- 3. reproduction ----------
.birthpass:
    mov   r12, orgs
.borneloop:
    mov   eax, [g_org_count]
    imul  rax, rax, ORG_STRIDE
    lea   r14, [orgs + rax]
    cmp   r12, r14
    jae   .compact
    test  qword [r12+O_FLAGS], ORG_DEAD
    jnz   .bornenext
    mov   rax, [r12+O_ENERGY]
    cmp   rax, [r12+O_REPRO]
    jl    .bornenext
    cmp   rax, BIRTH_MIN_EN
    jl    .bornenext
    cmp   dword [g_org_count], MAX_ORG
    jae   .bornenext
    ; child appended at array end
    mov   ecx, [g_org_count]
    imul  r10, rcx, ORG_STRIDE
    lea   r15, [orgs + r10]         ; pChild
    mov   r9d, 17                   ; copy whole record (17 qwords)
.cp:
    dec   r9d
    mov   rax, [r12 + r9*8]
    mov   [r15 + r9*8], rax
    test  r9d, r9d
    jnz   .cp
    ; jitter position +-8 px around parent, clamped to dish
    mov   rcx, 17*FP
    call  rand_lt
    sub   rax, 8*FP
    add   rax, [r12+O_X]
    cmp   rax, 0
    jge   1f
    xor   eax, eax
1:  cmp   rax, WORLD_W*FP
    jbe   2f
    mov   rax, WORLD_W*FP - 1
2:  mov   [r15+O_X], rax
    mov   rcx, 17*FP
    call  rand_lt
    sub   rax, 8*FP
    add   rax, [r12+O_Y]
    cmp   rax, 0
    jge   3f
    xor   eax, eax
3:  cmp   rax, WORLD_H*FP
    jbe   4f
    mov   rax, WORLD_H*FP - 1
4:  mov   [r15+O_Y], rax
    ; split surplus energy equally; parent pays an extra birth tax
    mov   rax, [r12+O_ENERGY]
    sub   rax, [r12+O_REPRO]
    shr   rax, 1
    mov   [r15+O_ENERGY], rax
    mov   [r12+O_ENERGY], rax
    sub   qword [r12+O_ENERGY], BIRTH_TAX
    ; child counters
    mov   qword [r15+O_AGE], 0
    mov   qword [r15+O_FLAGS], 0
    mov   qword [r15+O_TIDX], -1
    mov   rax, [r12+O_GEN]
    inc   rax
    mov   [r15+O_GEN], rax
    cmp   rax, [g_max_gen]
    jbe   5f
    mov   [g_max_gen], rax
5:  inc   dword [g_stat_births]
    ; ecological strategy follows the diet gene: lineages drift
    ; across the gatherer/predator boundary as DIET evolves past 500
    mov   rax, [r15+O_DIET]
    cmp   rax, 500
    jb    6f
    mov   qword [r15+O_TYPE], 1
    jmp   7f
6:  mov   qword [r15+O_TYPE], 0
7:  mov   rcx, r15
    call  mutate_child
    inc   dword [g_org_count]
.bornenext:
    add   r12, ORG_STRIDE
    jmp   .borneloop

    ; ---------- 4. compaction (remove DEAD records) ----------
.compact:
    xor   esi, esi                  ; scan index i
.cloop:
    cmp   esi, [g_org_count]
    jge   .envpass
    imul  rax, rsi, ORG_STRIDE
    lea   r10, [orgs + rax]         ; pCur
    test  qword [r10+O_FLAGS], ORG_DEAD
    jz    .cadv
    ; search backwards from the tail for a live replacement
    mov   edx, [g_org_count]
    dec   edx                       ; j
.findlast:
    cmp   edx, esi
    jbe   .cshrink                  ; none available -> plain shrink
    imul  rax, rdx, ORG_STRIDE
    lea   r11, [orgs + rax]
    test  qword [r11+O_FLAGS], ORG_DEAD
    jz    .cswap
    dec   edx
    jmp   .findlast
.cswap:
    mov   r9d, 17
.csw:
    dec   r9d
    mov   rax, [r11 + r9*8]
    mov   [r10 + r9*8], rax
    test  r9d, r9d
    jnz   .csw
    inc   dword [g_stat_deaths]
    mov   eax, [g_org_count]
    dec   eax
    mov   [g_org_count], eax
    jmp   .cloop                    ; re-examine i (new record there)
.cshrink:
    inc   dword [g_stat_deaths]
    mov   eax, [g_org_count]
    dec   eax
    mov   [g_org_count], eax
    jmp   .cloop
.cadv:
    inc   esi
    jmp   .cloop

    ; ---------- 5. environment drift ----------
.envpass:
    ; temperature: triangle wave, period 2400 ticks, range 250..750
    ; (permille scale around the comfortable midpoint 500)
    mov   eax, [g_env_phase]
    inc   eax
    cmp   eax, 2400
    jb    8f
    sub   eax, 2400
8:  mov   [g_env_phase], eax
    mov   ecx, eax
    cmp   ecx, 1200
    jbe   9f
    mov   ecx, 2400
    sub   ecx, eax                  ; tri = 0..1200..0
9:  mov   edx, ecx
    shr   edx, 1
    add   edx, 250
    mov   [g_temp], edx             ; temp = 250 + tri/2
    ; sunlight inversely coupled to temperature (range 400..900)
    mov   ecx, 1150
    sub   ecx, edx
    mov   [g_sun], ecx
    ; toxicity: slow decay; onset probability grows with crowding
    ; (population pressure poisons the dish - classic crash dynamics)
    mov   eax, [g_tox]
    test  eax, eax
    jz    .toxroll
    dec   eax
    mov   [g_tox], eax
    jmp   .foodregen
.toxroll:
    ; threshold = pop^2/4096 compared against roll 0..19999
    mov   eax, [g_org_count]
    imul  eax, eax
    shr   eax, 12
    mov   r9d, eax
    mov   ecx, 20000
    call  rand_lt
    cmp   rax, r9
    jae   .foodregen
    mov   rcx, 201
    call  rand_lt
    add   rax, 50
    mov   [g_tox], eax              ; new bloom: 50..250 permille
.foodregen:
    ; desired food = FOOD_TARGET*sun/1000; budget = gap*REGEN_NUM/1024
    mov   eax, FOOD_TARGET
    imul  eax, [g_sun]
    mov   ecx, 1000
    xor   edx, edx
    div   ecx
    sub   eax, [g_food_count]
    jle   .bloom
    imul  eax, eax, REGEN_NUM
    shr   eax, 10
    test  eax, eax
    jg    10f
    inc   eax                       ; at least one spawn attempt/tick
10: mov   r8d, eax                  ; budget
.spawnloop:
    test  r8d, r8d
    jle   .bloom
    call  spawn_food_one
    dec   r8d
    jmp   .spawnloop
.bloom:
    ; rare nutrient bloom (+250 food, expected ~once per 3000 ticks)
    mov   rcx, 3000
    call  rand_lt
    test  rax, rax
    jnz   .p2end
    mov   r8d, 250
11: test  r8d, r8d
    jle   .p2end
    call  spawn_food_one
    dec   r8d
    jmp   11b
.p2end:
    add   rsp, 0x20
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    pop   rdi
    pop   rsi
    pop   rbp
    pop   rbx
    ret

;=====================================================================
; mutate_child - rcx = pChild. Per trait: mutate when
; rand_lt(100) < O_MUTF; delta uniform in +-span (speed additionally
; scaled by MUTF/100); result clamped to global bounds. Modest rates
; keep lineages coherent while letting selection act over generations.
;=====================================================================
mutate_child:
    push  rbx
    sub   rsp, 0x20
    mov   rbx, rcx

    ; ----- speed: +-30 quanta * SPEED_MUT_SCALE, scaled by MUTF% -----
    mov   rcx, 100
    call  rand_lt
    mov   r9d, [rbx+O_MUTF]
    cmp   eax, r9d
    jae   .ms_done
    mov   rcx, 61
    call  rand_lt
    sub   eax, 30
    imul  eax, eax, SPEED_MUT_SCALE
    imul  eax, r9d
    mov   ecx, 100
    cdq                             ; sign-extend eax into edx:eax
    idiv  ecx                       ; eax = delta * MUTF / 100
    add   [rbx+O_SPEED], rax
    mov   rax, [rbx+O_SPEED]
    cmp   rax, 64                   ; floor 0.25 px/tick
    jge   1f
    mov   rax, 64
1:  cmp   rax, 1024                 ; ceiling 4.00 px/tick
    jle   2f
    mov   rax, 1024
2:  mov   [rbx+O_SPEED], rax
.ms_done:

    ; ----- metabolism index: +-10 (5..100) -----
    mov   rcx, 100
    call  rand_lt
    mov   r9d, [rbx+O_MUTF]
    cmp   eax, r9d
    jae   .mm_done
    mov   rcx, 21
    call  rand_lt
    sub   eax, 10
    add   [rbx+O_METAB], rax
    mov   rax, [rbx+O_METAB]
    cmp   rax, 5
    jge   3f
    mov   rax, 5
3:  cmp   rax, 100
    jle   4f
    mov   rax, 100
4:  mov   [rbx+O_METAB], rax
.mm_done:

    ; ----- sense radius: +-20 px (16..240) -----
    mov   rcx, 100
    call  rand_lt
    mov   r9d, [rbx+O_MUTF]
    cmp   eax, r9d
    jae   .sn_done
    mov   rcx, 41
    call  rand_lt
    sub   eax, 20
    add   [rbx+O_SENSE], rax
    mov   rax, [rbx+O_SENSE]
    cmp   rax, 16
    jge   5f
    mov   rax, 16
5:  cmp   rax, 240
    jle   6f
    mov   rax, 240
6:  mov   [rbx+O_SENSE], rax
.sn_done:

    ; ----- lifespan: +-300 ticks (300..6000) -----
    mov   rcx, 100
    call  rand_lt
    mov   r9d, [rbx+O_MUTF]
    cmp   eax, r9d
    jae   .ag_done
    mov   rcx, 601
    call  rand_lt
    sub   eax, 300
    add   [rbx+O_MAXAGE], rax
    mov   rax, [rbx+O_MAXAGE]
    cmp   rax, 300
    jge   7f
    mov   rax, 300
7:  cmp   rax, 6000
    jle   8f
    mov   rax, 6000
8:  mov   [rbx+O_MAXAGE], rax
.ag_done:

    ; ----- repro threshold: +-600 (4500..12000 fp) -----
    mov   rcx, 100
    call  rand_lt
    mov   r9d, [rbx+O_MUTF]
    cmp   eax, r9d
    jae   .rp_done
    mov   rcx, 1201
    call  rand_lt
    sub   eax, 600
    add   [rbx+O_REPRO], rax
    mov   rax, [rbx+O_REPRO]
    cmp   rax, 4500
    jge   9f
    mov   rax, 4500
9:  cmp   rax, 12000
    jle   10f
    mov   rax, 12000
10: mov   [rbx+O_REPRO], rax
.rp_done:

    ; ----- max energy: +-800 (6000..20000 fp) -----
    mov   rcx, 100
    call  rand_lt
    mov   r9d, [rbx+O_MUTF]
    cmp   eax, r9d
    jae   .mx_done
    mov   rcx, 1601
    call  rand_lt
    sub   eax, 800
    add   [rbx+O_MAXENR], rax
    mov   rax, [rbx+O_MAXENR]
    cmp   rax, 6000
    jge   11f
    mov   rax, 6000
11: cmp   rax, 20000
    jle   12f
    mov   rax, 20000
12: mov   [rbx+O_MAXENR], rax
.mx_done:

    ; ----- diet tendency: +-40 (0..1000) -----
    mov   rcx, 100
    call  rand_lt
    mov   r9d, [rbx+O_MUTF]
    cmp   eax, r9d
    jae   .dt_done
    mov   rcx, 81
    call  rand_lt
    sub   eax, 40
    add   [rbx+O_DIET], rax
    mov   rax, [rbx+O_DIET]
    test  rax, rax
    jns   13f
    xor   eax, eax
13: cmp   rax, 1000
    jle   14f
    mov   rax, 1000
14: mov   [rbx+O_DIET], rax
.dt_done:

    ; ----- mutation factor itself: +-10 percent (20..300) -----
    mov   rcx, 100
    call  rand_lt
    mov   r9d, [rbx+O_MUTF]
    cmp   eax, r9d
    jae   .mf_done
    mov   rcx, 21
    call  rand_lt
    sub   eax, 10
    add   [rbx+O_MUTF], rax
    mov   rax, [rbx+O_MUTF]
    cmp   rax, 20
    jge   15f
    mov   rax, 20
15: cmp   rax, 300
    jle   16f
    mov   rax, 300
16: mov   [rbx+O_MUTF], rax
.mf_done:

    add   rsp, 0x20
    pop   rbx
    ret

;=====================================================================
;                         R E N D E R I N G
;=====================================================================
; render_frame(hwnd): draw the whole scene into the bottom-up 32bpp
; DIB back-buffer (cur_w x cur_h = client size), then BitBlt it to
; the window. Screen row y maps to buffer row (cur_h-1-y). The dish
; is centered horizontally inside the client area. Organisms are
; filled disks: color = species, brightness = energy fraction.
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; plot_pixel: eax = screen x, ebx = screen y, ecx = color.
; Clipped against the current client rectangle. Preserves all
; registers except flags (uses r8/r9 internally... they are NOT
; preserved - caller must not rely on them; render_frame keeps its
; state in callee-saved regs only).
;---------------------------------------------------------------------
plot_pixel:
    test  eax, eax
    js    .pp_out                   ; x < 0
    cmp   eax, [cur_w]
    jge   .pp_out                   ; x >= w
    test  ebx, ebx
    js    .pp_out                   ; y < 0
    cmp   ebx, [cur_h]
    jge   .pp_out                   ; y >= h
    mov   r8d, [cur_h]
    dec   r8d
    sub   r8d, ebx                  ; bufrow = cur_h-1-y
    imul  r8, r8, [bpr]             ; * bytes per row
    lea   r9d, [rax*4]              ; x*4
    add   r8, r9
    add   r8, [bb_bits]
    mov   [r8], ecx
.pp_out:
    ret

render_frame:                       ; rcx = hwnd
    push  rbx
    push  rbp
    push  rsi
    push  rdi
    push  r12
    push  r13
    push  r14
    push  r15
    sub   rsp, 0x20

    mov   r12, rcx                  ; save hwnd across internal calls

    ; center dish horizontally inside current client width
    mov   eax, [cur_w]
    sub   eax, WORLD_W
    jns   1f
    xor   eax, eax
1:  shr   eax, 1
    mov   [dish_x], eax
    mov   dword [dish_y], OFFY

    ; ---- clear background (dark blue-black) ----
    mov   rdi, [bb_bits]
    mov   eax, [cur_w]
    imul  eax, [cur_h]
    shr   eax, 1                    ; two pixels packed per qword
    mov   ecx, eax
    mov   rax, 0x000A0A14000A0A14
    rep stosq

    ; ---- dish border rectangle (rim color 0x00383844) ----
    mov   ebx, [dish_x]             ; left x
    mov   ebp, [dish_y]             ; top y
    ; top and bottom horizontal lines
    xor   esi, esi
.bt:
    lea   eax, [rbx + rsi]
    mov   ecx, 0x00383844
    call  plot_pixel                ; top edge
    lea   eax, [rbp + WORLD_H-1]    ; bottom edge y
    mov   ebx?,                     ; (placeholder fixed below)
    inc   esi
    cmp   esi, WORLD_W
    jb    .bt
