/* linker.ld - Sonata flash programmer
 *
 * Everything in HyperRAM starting at 0x40000000.
 * Stack at 0x40700000 (grows downward).
 */

ENTRY(_start)

MEMORY
{
    ram (rwx) : ORIGIN = 0x40000000, LENGTH = 7M
}

SECTIONS
{
    .text : {
        *(.text.start)
        *(.text .text.*)
    } > ram

    .rodata : {
        *(.rodata .rodata.*)
    } > ram

    .data : {
        *(.data .data.*)
    } > ram

    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > ram

    _stack_top = 0x40700000;
}
