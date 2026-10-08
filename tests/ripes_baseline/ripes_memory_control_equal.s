.data
buffer:
    .word 0

.text
.globl main
main:
    li t2, 1048576       
    li t3, 1            
    la t0, buffer
    mv t1, t3

write_loop:
    sw t2, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -1
    beqz t2, finish

    addi t1, t1, -1
    bnez t1, write_loop

    la t0, buffer        
    mv t1, t3
    j write_loop

finish:
    li a7, 10
    ecall