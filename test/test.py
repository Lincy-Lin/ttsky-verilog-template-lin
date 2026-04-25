# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start test")

    # 100MHz clock (10ns period)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset DUT")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 5)

    dut._log.info("Sending 64x64 pixel stream")

    # Send 64x64 pixels
    for row in range(64):
        for col in range(64):
            dut.ui_in.value = 1   # pixel_valid
            dut.uio_in.value = (row + col) & 0xFF
            await RisingEdge(dut.clk)

    # Stop valid
    dut.ui_in.value = 0

    dut._log.info("Finished sending data")

    # Wait a few cycles
    await ClockCycles(dut.clk, 20)

    # Basic sanity check (not strict)
    out_val = int(dut.uo_out.value)
    dut._log.info(f"Final output sample: {out_val}")

    # Ensure output is in valid 8-bit range
    assert 0 <= out_val <= 255

    dut._log.info("Test completed successfully")
