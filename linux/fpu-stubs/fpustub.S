/* FPU stub libgcc.a — redirect soft-float ABI calls to hardware F+D instructions
 *
 * RV32 ILP32 soft-float calling convention:
 *   float args in a0, a1; return in a0
 *   double args in a0:a1 (lo:hi), a2:a3; return in a0:a1 (lo:hi)
 *
 * Build: riscv32-...-gcc -c -march=rv32imafd -mabi=ilp32 -o fpustub.o fpustub.S
 *        riscv32-...-ar rcs libgcc.a fpustub.o
 */

/* ===== Float arithmetic (4) ===== */

.globl __addsf3
__addsf3:
	fmv.w.x	fa0, a0
	fmv.w.x	fa1, a1
	fadd.s		fa0, fa0, fa1
	fmv.x.w	a0, fa0
	ret

.globl __subsf3
__subsf3:
	fmv.w.x	fa0, a0
	fmv.w.x	fa1, a1
	fsub.s		fa0, fa0, fa1
	fmv.x.w	a0, fa0
	ret

.globl __mulsf3
__mulsf3:
	fmv.w.x	fa0, a0
	fmv.w.x	fa1, a1
	fmul.s		fa0, fa0, fa1
	fmv.x.w	a0, fa0
	ret

.globl __divsf3
__divsf3:
	fmv.w.x	fa0, a0
	fmv.w.x	fa1, a1
	fdiv.s		fa0, fa0, fa1
	fmv.x.w	a0, fa0
	ret

/* ===== Double arithmetic (4) ===== */

.globl __adddf3
__adddf3:
	addi	sp, sp, -16
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	sw	a2, 8(sp)
	sw	a3, 12(sp)
	fld	fa0, 0(sp)
	fld	fa1, 8(sp)
	fadd.d	fa0, fa0, fa1
	fsd	fa0, 0(sp)
	lw	a0, 0(sp)
	lw	a1, 4(sp)
	addi	sp, sp, 16
	ret

.globl __subdf3
__subdf3:
	addi	sp, sp, -16
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	sw	a2, 8(sp)
	sw	a3, 12(sp)
	fld	fa0, 0(sp)
	fld	fa1, 8(sp)
	fsub.d	fa0, fa0, fa1
	fsd	fa0, 0(sp)
	lw	a0, 0(sp)
	lw	a1, 4(sp)
	addi	sp, sp, 16
	ret

.globl __muldf3
__muldf3:
	addi	sp, sp, -16
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	sw	a2, 8(sp)
	sw	a3, 12(sp)
	fld	fa0, 0(sp)
	fld	fa1, 8(sp)
	fmul.d	fa0, fa0, fa1
	fsd	fa0, 0(sp)
	lw	a0, 0(sp)
	lw	a1, 4(sp)
	addi	sp, sp, 16
	ret

.globl __divdf3
__divdf3:
	addi	sp, sp, -16
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	sw	a2, 8(sp)
	sw	a3, 12(sp)
	fld	fa0, 0(sp)
	fld	fa1, 8(sp)
	fdiv.d	fa0, fa0, fa1
	fsd	fa0, 0(sp)
	lw	a0, 0(sp)
	lw	a1, 4(sp)
	addi	sp, sp, 16
	ret

/* ===== Float comparisons (6) =====
 *
 * __eqsf2 / __nesf2 / __ltsf2 / __lesf2: NaN → return 1 (nonzero = unequal/not-less)
 * __gtsf2 / __gesf2: NaN → return -1 (nonzero = not-greater)
 *
 * libgcc comparison contract:
 *   return -1 if a < b
 *   return  0 if a == b
 *   return  1 if a > b
 *   return NaN-default if unordered
 */

.globl __eqsf2
.globl __nesf2
.globl __ltsf2
.globl __lesf2
__eqsf2:
__nesf2:
__ltsf2:
__lesf2:
	fmv.w.x	fa0, a0
	fmv.w.x	fa1, a1
	flt.s		a0, fa0, fa1	/* a0 = (a < b) */
	bnez		a0, .Lsf_ret_neg1
	fle.s		a0, fa0, fa1	/* a0 = (a <= b) */
	bnez		a0, .Lsf_ret_0
	li		a0, 1		/* a > b, or NaN */
	ret
.Lsf_ret_neg1:
	li		a0, -1
	ret
.Lsf_ret_0:
	li		a0, 0
	ret

.globl __gtsf2
.globl __gesf2
__gtsf2:
__gesf2:
	fmv.w.x	fa0, a0
	fmv.w.x	fa1, a1
	flt.s		a0, fa1, fa0	/* a0 = (b < a) i.e. a > b */
	bnez		a0, .Lsf_gt_ret_1
	fle.s		a0, fa1, fa0	/* a0 = (b <= a) i.e. a >= b */
	bnez		a0, .Lsf_gt_ret_0
	li		a0, -1		/* a < b, or NaN */
	ret
.Lsf_gt_ret_1:
	li		a0, 1
	ret
.Lsf_gt_ret_0:
	li		a0, 0
	ret

/* ===== Double comparisons (6) ===== */

.globl __eqdf2
.globl __nedf2
.globl __ltdf2
.globl __ledf2
__eqdf2:
__nedf2:
__ltdf2:
__ledf2:
	addi	sp, sp, -16
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	sw	a2, 8(sp)
	sw	a3, 12(sp)
	fld	fa0, 0(sp)
	fld	fa1, 8(sp)
	flt.d	a0, fa0, fa1
	bnez	a0, .Ldf_ret_neg1
	fle.d	a0, fa0, fa1
	bnez	a0, .Ldf_ret_0
	li	a0, 1
	addi	sp, sp, 16
	ret
.Ldf_ret_neg1:
	li	a0, -1
	addi	sp, sp, 16
	ret
.Ldf_ret_0:
	li	a0, 0
	addi	sp, sp, 16
	ret

.globl __gtdf2
.globl __gedf2
__gtdf2:
__gedf2:
	addi	sp, sp, -16
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	sw	a2, 8(sp)
	sw	a3, 12(sp)
	fld	fa0, 0(sp)
	fld	fa1, 8(sp)
	flt.d	a0, fa1, fa0
	bnez	a0, .Ldf_gt_ret_1
	fle.d	a0, fa1, fa0
	bnez	a0, .Ldf_gt_ret_0
	li	a0, -1
	addi	sp, sp, 16
	ret
.Ldf_gt_ret_1:
	li	a0, 1
	addi	sp, sp, 16
	ret
.Ldf_gt_ret_0:
	li	a0, 0
	addi	sp, sp, 16
	ret

/* ===== Int32 → float/double conversions (4) ===== */

.globl __floatsisf
__floatsisf:
	fcvt.s.w	fa0, a0
	fmv.x.w	a0, fa0
	ret

.globl __floatsidf
__floatsidf:
	addi	sp, sp, -8
	fcvt.d.w	fa0, a0
	fsd		fa0, 0(sp)
	lw		a0, 0(sp)
	lw		a1, 4(sp)
	addi	sp, sp, 8
	ret

.globl __floatunsisf
__floatunsisf:
	fcvt.s.wu	fa0, a0
	fmv.x.w	a0, fa0
	ret

.globl __floatunsidf
__floatunsidf:
	addi	sp, sp, -8
	fcvt.d.wu	fa0, a0
	fsd		fa0, 0(sp)
	lw		a0, 0(sp)
	lw		a1, 4(sp)
	addi	sp, sp, 8
	ret

/* ===== Float/double → int32 conversions (4) ===== */

.globl __fixsfsi
__fixsfsi:
	fmv.w.x	fa0, a0
	fcvt.w.s	a0, fa0, rtz
	ret

.globl __fixdfsi
__fixdfsi:
	addi	sp, sp, -8
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	fld	fa0, 0(sp)
	fcvt.w.d	a0, fa0, rtz
	addi	sp, sp, 8
	ret

.globl __fixunssfsi
__fixunssfsi:
	fmv.w.x	fa0, a0
	fcvt.wu.s	a0, fa0, rtz
	ret

.globl __fixunsdfsi
__fixunsdfsi:
	addi	sp, sp, -8
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	fld	fa0, 0(sp)
	fcvt.wu.d	a0, fa0, rtz
	addi	sp, sp, 8
	ret

/* ===== Float ↔ double conversions (2) ===== */

.globl __extendsfdf2
__extendsfdf2:
	addi	sp, sp, -8
	fmv.w.x	fa0, a0
	fcvt.d.s	fa0, fa0
	fsd		fa0, 0(sp)
	lw		a0, 0(sp)
	lw		a1, 4(sp)
	addi	sp, sp, 8
	ret

.globl __truncdfsf2
__truncdfsf2:
	addi	sp, sp, -8
	sw	a0, 0(sp)
	sw	a1, 4(sp)
	fld	fa0, 0(sp)
	fcvt.s.d	fa0, fa0
	fmv.x.w	a0, fa0
	addi	sp, sp, 8
	ret

/* ===== Int64 → float/double conversions (4) =====
 *
 * Strategy: convert high and low 32-bit halves separately using double
 * precision, combine, then optionally narrow to float.
 *
 * For signed: high word is sign-extended (fcvt.d.w), low word is unsigned (fcvt.d.wu)
 * For unsigned: both words use fcvt.d.wu
 *
 * Input: a0 = low 32 bits, a1 = high 32 bits
 *
 * Constant 2^32 = 4294967296.0 = 0x41F0000000000000
 */

.globl __floatdisf
__floatdisf:
	/* signed int64 → float */
	addi	sp, sp, -8
	fcvt.d.w	fa1, a1		/* fa1 = (double)(int32_t)high */
	lui		a1, 0x41f00	/* 0x41F00000 = high word of 2^32 */
	sw		zero, 0(sp)
	sw		a1, 4(sp)
	fld		fa2, 0(sp)	/* fa2 = 2^32 */
	fmul.d		fa1, fa1, fa2	/* fa1 = high * 2^32 */
	fcvt.d.wu	fa0, a0		/* fa0 = (double)(uint32_t)low */
	fadd.d		fa0, fa1, fa0	/* fa0 = high*2^32 + low */
	fcvt.s.d	fa0, fa0	/* narrow to float */
	fmv.x.w	a0, fa0
	addi	sp, sp, 8
	ret

.globl __floatdidf
__floatdidf:
	/* signed int64 → double */
	addi	sp, sp, -8
	fcvt.d.w	fa1, a1		/* fa1 = (double)(int32_t)high */
	lui		a1, 0x41f00	/* high word of 2^32 */
	sw		zero, 0(sp)
	sw		a1, 4(sp)
	fld		fa2, 0(sp)	/* fa2 = 2^32 */
	fmul.d		fa1, fa1, fa2	/* fa1 = high * 2^32 */
	fcvt.d.wu	fa0, a0		/* fa0 = (double)(uint32_t)low */
	fadd.d		fa0, fa1, fa0	/* fa0 = high*2^32 + low */
	fsd		fa0, 0(sp)
	lw		a0, 0(sp)
	lw		a1, 4(sp)
	addi	sp, sp, 8
	ret

.globl __floatundisf
__floatundisf:
	/* unsigned int64 → float */
	addi	sp, sp, -8
	fcvt.d.wu	fa1, a1		/* fa1 = (double)(uint32_t)high */
	lui		a1, 0x41f00
	sw		zero, 0(sp)
	sw		a1, 4(sp)
	fld		fa2, 0(sp)	/* fa2 = 2^32 */
	fmul.d		fa1, fa1, fa2
	fcvt.d.wu	fa0, a0		/* fa0 = (double)(uint32_t)low */
	fadd.d		fa0, fa1, fa0
	fcvt.s.d	fa0, fa0
	fmv.x.w	a0, fa0
	addi	sp, sp, 8
	ret

.globl __floatundidf
__floatundidf:
	/* unsigned int64 → double */
	addi	sp, sp, -8
	fcvt.d.wu	fa1, a1		/* fa1 = (double)(uint32_t)high */
	lui		a1, 0x41f00
	sw		zero, 0(sp)
	sw		a1, 4(sp)
	fld		fa2, 0(sp)	/* fa2 = 2^32 */
	fmul.d		fa1, fa1, fa2
	fcvt.d.wu	fa0, a0		/* fa0 = (double)(uint32_t)low */
	fadd.d		fa0, fa1, fa0
	fsd		fa0, 0(sp)
	lw		a0, 0(sp)
	lw		a1, 4(sp)
	addi	sp, sp, 8
	ret
