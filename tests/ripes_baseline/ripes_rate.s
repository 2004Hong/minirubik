.data
buffer:
    .zero 4096

.text
.globl main
main:
    li t2, 2500

outer_loop:
    la t0, buffer
    li t1, 1024

write_loop:
    sw t1, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, write_loop

    addi t2, t2, -1
    bnez t2, outer_loop

    li a7, 10
    ecall