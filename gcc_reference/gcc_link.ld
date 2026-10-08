OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = 0;
    .text : {
        *(.text.start)
        *(.text .text.*)
    }

    . = 0x10000000;
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    }

    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    }

    .bss (NOLOAD) : {
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
    }

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame*)
    }
}