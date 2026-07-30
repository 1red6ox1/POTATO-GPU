/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include "rvlab.h"
#include "dma.h"
#include "memcpy.h"

void memcpy_soft(void *dest, void *src, uint32_t length) {
    int * prt_src = (int *) src;
    int * prt_dst = (int *) dest;
    for(int i=0; i < (length/sizeof(int)); i++) {
        prt_dst[i] = prt_src[i];
    }
}

void memcpy_dma(void *dest, void *src, uint32_t length) {
    volatile dma_descriptor_t d;
    
    d.operation = DMA_OP_MEMCPY;
    d.dst_adr   = (uint32_t) dest;
    d.src_adr   = (uint32_t) src;
    d.length    = length;
    
    dma_write_desc(&d);
    dma_wait();
}
