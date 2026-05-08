/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2026 RVLab Contributors
 */
#include <stdio.h>
#include <rvlab.h>

// Exception Causes [adapted from src/rtl/cv32e40p/pkg/cv32e40p_pkg.sv]
#define EXC_CAUSE_INSTR_FAULT 0x01
#define EXC_CAUSE_ILLEGAL_INSN 0x02
#define EXC_CAUSE_BREAKPOINT 0x03
#define EXC_CAUSE_LOAD_FAULT 0x05
#define EXC_CAUSE_STORE_FAULT 0x07
#define EXC_CAUSE_ECALL_UMODE 0x08
#define EXC_CAUSE_ECALL_MMODE 0x0B

static const char *mcause_to_string(uint32_t mcause) {
	mcause = mcause & 0x1F; // extract exception code
	switch (mcause) {
		case EXC_CAUSE_INSTR_FAULT : return "INSTR_FAULT";
		case EXC_CAUSE_ILLEGAL_INSN: return "ILLEGAL_INSN";
		case EXC_CAUSE_BREAKPOINT  : return "BREAKPOINT";
		case EXC_CAUSE_LOAD_FAULT  : return "LOAD_FAULT";
		case EXC_CAUSE_STORE_FAULT : return "STORE_FAULT";
		case EXC_CAUSE_ECALL_UMODE : return "ECALL_UMODE";
		case EXC_CAUSE_ECALL_MMODE : return "ECALL_MMODE";
		default: return "Unknown mcause";
	}
}

uint32_t rvlab_irq_error(void) {
	// IRQ error encountered, read MCause to direct error handling

	uint32_t mepc = read_csr("mepc");
	uint32_t mcause = read_csr("mcause");

	if (mcause & 0x80000000) {
		printf("Encountered IRQ Error, MEPC: 0x%08x, MCAUSE: 0x%08x\n", mepc, mcause);
		return -1;
	}

	printf("Encountered internal exception, MEPC: 0x%08x, MCAUSE: %s\n",
		mepc, mcause_to_string(mcause));
	return -2;
}
