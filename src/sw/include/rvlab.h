/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#ifndef _RVLAB_H
#define _RVLAB_H

#define IRQ_TIMER 7
#define IRQ_EXTERNAL 11

#define DDR3_BASE_ADDR ((void *) 0x80000000)
#define DDR3_SIZE      ((size_t) 0x20000000)

int ddr_init(void);

#include <regaccess.h>

#include <reggen/ddr_ctrl.h>
#define DDR_CTRL0_BASE_ADDR 0x1f001000

#include <reggen/regdemo.h>
#define REGDEMO0_BASE_ADDR 0x1f002000

#include <reggen/rv_timer.h>
#define RV_TIMER0_BASE_ADDR 0x1f000000

#include <reggen/student_dma.h>
#define STUDENT_DMA0_BASE_ADDR 0x20000000

#include <reggen/student_rlight.h>
#define STUDENT_RLIGHT0_BASE_ADDR 0x10000000

#include <reggen/student_irq_ctrl.h>
#define STUDENT_IRQ_CTRL0_BASE_ADDR 0x10100000

#include <reggen/hdmi_ctrl.h>
#define HDMI_CTRL0_BASE_ADDR 0x10200000

#include <reggen/frameclear_dma.h>
#define FRAMECLEAR_DMA0_BASE_ADDR 0x10300000

#include <reggen/matmul_ctrl.h>
#define MATMUL_CTRL0_BASE_ADDR 0x10400000
#define VERTEX_DATA0_BASE_ADDR 0x10500000

#endif // _RVLAB_H
