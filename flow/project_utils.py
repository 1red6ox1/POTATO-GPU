# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 David Schröder

from pydesignflow import Block, task, Result
from .tools import openocd, gif_util, riscv_debug_helper
from io import StringIO

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
	def prepare_gif(self, cwd):
		print("Analyzing input file...")
		palette, frame_indices, ms_times = gif_util.convert_gif(
			self.design_dir / "project/texture.gif", (32, 32), 256, False
		)

		print("Decoded %d frames (%d cyc/frame)!" % (len(frame_indices), ms_times[0]*50000))

		print("Generating palette binary...")
		with open(cwd / "palette.bin", "wb") as wfile:
			for color in palette:
				wfile.write(self._color(*color).to_bytes(4, byteorder="little"))
		print("Done!")

		print("Generating texture binary...")
		with open(cwd / "texture.bin", "wb") as wfile:
			for i, idxs in enumerate(frame_indices):
				print("%5d/%5d" % (i+1, len(frame_indices)), end="\r")
				for uv, idx in enumerate(idxs):
					u = uv // 32
					v = uv % 32
					wfile.write(idx.to_bytes(4, byteorder="little"))
		print("Done!               ")


		r = Result()
		r.palette_file = cwd / "palette.bin"
		r.texture_file = cwd / "texture.bin"

		return r

	@task(requires={
		"gif": ".prepare_gif"
	})
	def load_gif(self, cwd, gif):
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

			# Load both memfiles
			ocd.cmd(f"load_image {gif.palette_file} {self.PALETTE_RAM} bin")
			ocd.cmd(f"load_image {gif.texture_file} {self.VIDEO_BASE} bin")

	@task()
	def prepare_image(self, cwd):
		print("Analyzing input file...", end=" ")
		palette, chunks = gif_util.image_to_chunks(self.design_dir / "project/texture.png")
		print("Done!")

		print("Generating palette binary...")
		with open(cwd / "palette.bin", "wb") as wfile:
			for color in palette:
				wfile.write(self._color(*color).to_bytes(4, byteorder="little"))
		print("Done!")

		print("Generating texture binary...")
		with open(cwd / "texture.bin", "wb") as wfile:
			for i, idxs in enumerate(chunks):
				print("%5d/%5d" % (i+1, 16), end="\r")
				for uv, idx in enumerate(idxs):
					u = uv // 32
					v = uv % 32
					wfile.write(idx.to_bytes(4, byteorder="little"))
		print("Done!               ")


		r = Result()
		r.palette_file = cwd / "palette.bin"
		r.texture_file = cwd / "texture.bin"

		return r

	@task(requires={
		"png": ".prepare_image"
	})
	def load_image(self, cwd, png):
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

			# Load both memfiles
			ocd.cmd(f"load_image {png.palette_file} {self.PALETTE_RAM} bin")
			ocd.cmd(f"load_image {png.texture_file} {self.VIDEO_BASE} bin")
