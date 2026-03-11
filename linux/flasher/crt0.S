/* crt0.S - Minimal startup for Sonata flash programmer
 *
 * Runs in M-mode from HyperRAM at 0x40000000.
 * Hart 0: disables interrupts, sets stack, clears BSS, calls main().
 * Other harts: park immediately in WFI loop.
 */

.section .text.start
.globl _start
_start:
	/* Park non-boot harts */
	csrr	t0, mhartid
	bnez	t0, .Lpark

	/* Disable interrupts */
	csrw	mie, zero
	csrci	mstatus, 8		/* Clear MIE in mstatus */

	/* Set stack pointer */
	la	sp, _stack_top

	/* Clear BSS */
	la	t0, _bss_start
	la	t1, _bss_end
1:
	bge	t0, t1, 2f
	sw	zero, 0(t0)
	addi	t0, t0, 4
	j	1b
2:
	/* Call main */
	call	main

	/* Infinite loop on return */
.Lpark:
	wfi
	j	.Lpark
