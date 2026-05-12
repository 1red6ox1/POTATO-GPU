# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 RVLab Contributors

# DMI Utilities for OpenOCD startup.
# More or less mirrors functionality of src/tb/rvlab_test_utils.sv

from enum import Enum


class DMCSR(Enum):
	DMControl = 0x10
	DMStatus  = 0x11


def dmi_write(ocd, addr: DMCSR, value: int):
	ocd.cmd(f"riscv dmi_write {addr.value} {value}")

def dmi_read(ocd, addr: DMCSR):
	raw = ocd.cmd(f"riscv dmi_read {addr.value}")
	return int(raw, 0)


class DMControl:
	def __init__(self, ocd):
		self.haltreq         = 0
		self.resumereq       = 0
		self.hartreset       = 0
		self.ackhavereset    = 0
		self.hasel           = 0
		self.hartsello       = 0
		self.hartselhi       = 0
		self.setresethaltreq = 0
		self.clrresethaltreq = 0
		self.ndmreset        = 0
		self.dmactive        = 0
		self._ocd = ocd

	def write(self):
		"""Update flags in DM Control register"""
		"""Field positions extracted from RISC-V Debug Spec v0.13.2"""
		serial = 0
		serial |= (  0x1 & self.haltreq        ) << 31
		serial |= (  0x1 & self.resumereq      ) << 30
		serial |= (  0x1 & self.hartreset      ) << 29
		serial |= (  0x1 & self.ackhavereset   ) << 28
		serial |= (  0x1 & self.hasel          ) << 26
		serial |= (0x3FF & self.hartsello      ) << 16
		serial |= (0x3FF & self.hartselhi      ) << 6
		serial |= (  0x1 & self.setresethaltreq) << 3
		serial |= (  0x1 & self.clrresethaltreq) << 2
		serial |= (  0x1 & self.ndmreset       ) << 1
		serial |= (  0x1 & self.dmactive       ) << 0
		dmi_write(self._ocd, DMCSR.DMControl, serial)


class DMStatus:
	def __init__(self, ocd):
		self.impebreak       = 0
		self.allhavereset    = 0
		self.anyhavereset    = 0
		self.allresumeack    = 0
		self.anyresumeack    = 0
		self.allnonexistent  = 0
		self.anynonexistent  = 0
		self.allunavail      = 0
		self.anyunavail      = 0
		self.allrunning      = 0
		self.anyrunning      = 0
		self.allhalted       = 0
		self.anyhalted       = 0
		self.authenticated   = 0
		self.authbusy        = 0
		self.hasresethaltreq = 0
		self.devtreevalid    = 0
		self.version         = 0
		self._ocd = ocd

	def read(self):
		"""Update flags from DM Status register"""
		"""Field positions extracted from RISC-V Debug Spec v0.13.2"""
		value = dmi_read(self._ocd, DMCSR.DMStatus)
		self.impebreak       = (value >> 22) & 0x1
		self.allhavereset    = (value >> 19) & 0x1
		self.anyhavereset    = (value >> 18) & 0x1
		self.allresumeack    = (value >> 17) & 0x1
		self.anyresumeack    = (value >> 16) & 0x1
		self.allnonexistent  = (value >> 15) & 0x1
		self.anynonexistent  = (value >> 14) & 0x1
		self.allunavail      = (value >> 13) & 0x1
		self.anyunavail      = (value >> 12) & 0x1
		self.allrunning      = (value >> 11) & 0x1
		self.anyrunning      = (value >> 10) & 0x1
		self.allhalted       = (value >>  9) & 0x1
		self.anyhalted       = (value >>  8) & 0x1
		self.authenticated   = (value >>  7) & 0x1
		self.authbusy        = (value >>  6) & 0x1
		self.hasresethaltreq = (value >>  5) & 0x1
		self.devtreevalid    = (value >>  4) & 0x1
		self.version         = (value >>  0) & 0xF
		return self


def dm_start(dmcontrol: DMControl, dmstatus: DMStatus):
	dmcontrol.dmactive = 1
	dmcontrol.write()


def dm_ndmreset(dmcontrol: DMControl, dmstatus: DMStatus):
	dmcontrol.ndmreset = 1
	dmcontrol.write()

	while not dmstatus.read().allhavereset: pass

	dmcontrol.ndmreset = 0
	dmcontrol.write()

def dm_ackhavereset(dmcontrol: DMControl, dmstatus: DMStatus):
	dmcontrol.ackhavereset = 1
	dmcontrol.write()
	dmcontrol.ackhavereset = 0
	dmcontrol.write()

def dm_set_resethaltreq(dmcontrol: DMControl, dmstatus: DMStatus):
	dmcontrol.setresethaltreq = 1
	dmcontrol.write()
	dmcontrol.setresethaltreq = 0
	dmcontrol.write()

def dm_clear_resethaltreq(dmcontrol: DMControl, dmstatus: DMStatus):
	dmcontrol.clrresethaltreq = 1
	dmcontrol.write()
	dmcontrol.clrresethaltreq = 0
	dmcontrol.write()

def reset_halt_rvlab_cpu(ocd):
	ctrl = DMControl(ocd)
	status = DMStatus(ocd)

	dm_start(ctrl, status)

	# Setup + Set reset halt request bit in DM
	dm_ackhavereset(ctrl, status)
	dm_set_resethaltreq(ctrl, status)

	# Send CPU into halted state via reset halt
	dm_ndmreset(ctrl, status)

	# Reset status + reset halt request bit
	dm_ackhavereset(ctrl, status)
	dm_clear_resethaltreq(ctrl, status)
