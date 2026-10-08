.section .text.start,"ax",@progbits
.globl _start

_start:
    la sp, stack_top
    call main

    li a7, 10
    ecall

.section .bss
.align 4

stack_bottom:
    .zero 4096
stack_top: