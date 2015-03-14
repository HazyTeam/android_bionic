/* Copyright (c) 2013, Linaro Limited
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

      * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.

      * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

      * Neither the name of Linaro Limited nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
   This memcpy routine is optimised for Cortex-A15 cores and takes advantage
   of VFP or NEON when built with the appropriate flags.

   Assumptions:

    ARMv6 (ARMv7-a if using Neon)
    ARM state
    Unaligned accesses

   Ported to work inside Bionic by Bernhard Rosenkränzer <bero@linaro.org>
 */

#include <private/bionic_asm.h>
#include <private/libc_events.h>

	.syntax unified
	/* This implementation requires ARM state.  */
	.arm

#ifdef __ARM_NEON__

	.fpu	neon
	.arch	armv7-a
# define FRAME_SIZE	4
# define USE_VFP
# define USE_NEON

#elif !defined (__SOFTFP__)
#error VFP

	.arch	armv6
	.fpu	vfpv2
# define FRAME_SIZE	32
# define USE_VFP

#else
#error NO FPU
	.arch	armv6
# define FRAME_SIZE    32

#endif

/* Old versions of GAS incorrectly implement the NEON align semantics.  */
#ifdef BROKEN_ASM_NEON_ALIGN
#define ALIGN(addr, align) addr,:align
#else
#define ALIGN(addr, align) addr:align
#endif

#define PC_OFFSET	8	/* PC pipeline compensation.  */
#define INSN_SIZE	4

/* Call parameters.  */
#define dstin	r0
#define src	r1
#define count	r2

/* Locals.  */
#define tmp1	r3
#define dst	ip
#define tmp2	r10

#ifndef USE_NEON
/* For bulk copies using GP registers.  */
#define	A_l	r2		/* Call-clobbered.  */
#define	A_h	r3		/* Call-clobbered.  */
#define	B_l	r4
#define	B_h	r5
#define	C_l	r6
#define	C_h	r7
#define	D_l	r8
#define	D_h	r9
#endif

/* Number of lines ahead to pre-fetch data.  If you change this the code
   below will need adjustment to compensate.  */

#define prefetch_lines	5

#ifdef USE_VFP
	.macro	cpy_line_vfp vreg, base
	vstr	\vreg, [dst, #\base]
	vldr	\vreg, [src, #\base]
	vstr	d0, [dst, #\base + 8]
	vldr	d0, [src, #\base + 8]
	vstr	d1, [dst, #\base + 16]
	vldr	d1, [src, #\base + 16]
	vstr	d2, [dst, #\base + 24]
	vldr	d2, [src, #\base + 24]
	vstr	\vreg, [dst, #\base + 32]
	vldr	\vreg, [src, #\base + prefetch_lines * 64 - 32]
	vstr	d0, [dst, #\base + 40]
	vldr	d0, [src, #\base + 40]
	vstr	d1, [dst, #\base + 48]
	vldr	d1, [src, #\base + 48]
	vstr	d2, [dst, #\base + 56]
	vldr	d2, [src, #\base + 56]
	.endm

	.macro	cpy_tail_vfp vreg, base
	vstr	\vreg, [dst, #\base]
	vldr	\vreg, [src, #\base]
	vstr	d0, [dst, #\base + 8]
	vldr	d0, [src, #\base + 8]
	vstr	d1, [dst, #\base + 16]
	vldr	d1, [src, #\base + 16]
	vstr	d2, [dst, #\base + 24]
	vldr	d2, [src, #\base + 24]
	vstr	\vreg, [dst, #\base + 32]
	vstr	d0, [dst, #\base + 40]
	vldr	d0, [src, #\base + 40]
	vstr	d1, [dst, #\base + 48]
	vldr	d1, [src, #\base + 48]
	vstr	d2, [dst, #\base + 56]
	vldr	d2, [src, #\base + 56]
	.endm
#endif

ENTRY(__memcpy_chk)
        cmp         r2, r3
        bhi         __memcpy_chk_fail

        // Fall through to memcpy...
END(__memcpy_chk)

ENTRY(memcpy)
        pld     [r1, #64]
        push    {r0, lr}
        .cfi_def_cfa_offset 8
        .cfi_rel_offset r0, 0
        .cfi_rel_offset lr, 4
END(memcpy)

#define MEMCPY_BASE         __memcpy_base
#define MEMCPY_BASE_ALIGNED __memcpy_base_aligned
#include "memcpy_base.S"

ENTRY_PRIVATE(__memcpy_chk_fail)
        // Preserve lr for backtrace.
        push    {lr}
        .cfi_def_cfa_offset 4
        .cfi_rel_offset lr, 0

        ldr     r0, error_message
        ldr     r1, error_code
1:
        add     r0, pc
        bl      __fortify_chk_fail
error_code:
        .word   BIONIC_EVENT_MEMCPY_BUFFER_OVERFLOW
error_message:
        .word   error_string-(1b+8)
END(__memcpy_chk_fail)

        .data
error_string:
        .string "memcpy: prevented write past end of buffer"
