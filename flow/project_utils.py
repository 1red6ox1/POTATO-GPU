# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 David Schröder

from pydesignflow import Block, task, Result
from .tools import openocd, gif_util, riscv_debug_helper

class ProjectUtils(Block):
    """
    Utilities for POTATO GPU Project
    """

    def setup(self):
        self.src_dir = self.flow.base_dir / "src"
        self.design_dir = self.src_dir / "design"
        self.TEXTURE_RAM = 0x10900000
        self.PALETTE_RAM = 0x10A00000
        self.VIDEO_BASE  = 0x90000000

    def _texram_at(self, texid, u, v):
    	addr = self.TEXTURE_RAM + ((texid << 10) | (u << 5) | v) * 4
    	return addr

    def _palram_at(self, colorid):
    	return self.PALETTE_RAM + colorid * 4

    def _vram_at(self, frameid, u, v):
    	return self.VIDEO_BASE + ((frameid << 10) | (u << 5) | v) * 4

    def _color(self, r, g, b):
    	return (r << 16) | (g << 8) | b

    @task()
    def clear_texdata(self, cwd):
    	with openocd.start(self.design_dir / "openocd/fpga.cfg") as ocd:
    		riscv_debug_helper.reset_halt_rvlab_cpu(ocd)
    		ocd.cmd("lpriscv1.tap.0 arp_examine")
    		riscv_debug_helper.reset_halt_rvlab_cpu(ocd)
    		ocd.hostio_clear()

    		#print("Loading Palette...")
    		#for i in range(256):
    		#	addr = self._palram_at(i)
    		#	ocd.writeword(addr, 0)
    		print("Loading frames...")
    		for i in range(32):
    			print(i)
    			for uv in range(1024):
    				u = uv // 32
    				v = uv % 32
    				addr = self._texram_at(i, u, v)
    				ocd.writeword(addr, 0)

    @task()
    def load_gif(self, cwd):
    	print("Analyzing input file...")
    	palette, frame_indices, _ = gif_util.convert_gif(
    		self.design_dir / "project/texture.gif", (32, 32), 256, False
    	)
    	with openocd.start(self.design_dir / "openocd/fpga.cfg") as ocd:
    		riscv_debug_helper.reset_halt_rvlab_cpu(ocd)
    		ocd.cmd("lpriscv1.tap.0 arp_examine")
    		riscv_debug_helper.reset_halt_rvlab_cpu(ocd)
    		ocd.hostio_clear()
    		ocd.cmd("riscv set_mem_access sysbus")

    		# Manually trigger DDR init
    		ocd.writeword(0x1f001004, 1)
    		while ocd.readword((0x1f001000 & 2) == 0): pass

    		print("DDR calibration completed.")

    		print("Loading Palette...")
    		for i, color in enumerate(palette):
    			colorval = self._color(*color)
    			addr = self._palram_at(i)
    			ocd.writeword(addr, colorval)
    		print("Loading frames...")
    		for i, idxs in enumerate(frame_indices):
    			print("%5d/%5d" % (i+1, len(frame_indices)), end="\r")
    			for uv, idx in enumerate(idxs):
    				u = uv // 32
    				v = uv % 32
    				addr = self._vram_at(i, u, v)
    				ocd.writeword(addr, idx)
    		print("Done!")
