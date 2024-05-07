# Store call-preserved registers in context struct
save_context:
# store rsp + 8 since the `call` decrease rsp by 8 bytes
add $8, %rsp
movq %rsp, 8(%rdi)
sub $8, %rsp

movq %rbp, 16(%rdi)
movq %rbx, 24(%rdi)
movq %r12, 32(%rdi)
movq %r13, 40(%rdi)
movq %r14, 48(%rdi)
movq %r15, 56(%rdi)

retq

restore_context:
movq 56(%rdi), %r15
movq 48(%rdi), %r14
movq 40(%rdi), %r13
movq 32(%rdi), %r12
movq 24(%rdi), %rbx
movq 16(%rdi), %rbp
movq  8(%rdi), %rsp

jmp *(%rdi)

switch_to_new_co:
# the first arg in %rdi is passed as is 
movq %rdx, %rsp
jmp *%rsi
