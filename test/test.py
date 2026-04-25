# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

IMG_SIZE     = 6
OUTPUT_BITS  = 8
OUTPUT_SHIFT = 8 - OUTPUT_BITS


# ─────────────────────────────────────────────────────────────
# Cycle-accurate RTL model
# ─────────────────────────────────────────────────────────────
def sobel_model(image, img_size=IMG_SIZE, output_bits=OUTPUT_BITS):

    output_shift = 8 - output_bits

    linebuf1 = [0] * img_size
    linebuf2 = [0] * img_size

    r0_0 = r0_1 = 0
    r1_0 = r1_1 = 0
    r2_0 = r2_1 = 0

    row = 0
    col = 0

    results = []

    for pixel_in in image:

        # ── combinational reads (BEFORE update) ──
        row1_col2 = linebuf1[col]
        row2_col2 = linebuf2[col]

        p00, p01, p02 = r2_0, r2_1, row2_col2
        p10,      p12 = r1_0, row1_col2
        p20, p21, p22 = r0_0, r0_1, pixel_in

        def s12(v):
            v &= 0xFFF
            return v - 0x1000 if v >= 0x800 else v

        gx = s12(-p00 + p02 - 2*p10 + 2*p12 - p20 + p22)
        gy = s12( p00 + 2*p01 + p02 - p20 - 2*p21 - p22)

        abs_gx = abs(gx)
        abs_gy = abs(gy)

        mag = abs_gx + abs_gy
        mag_sat8 = 0xFF if mag > 255 else mag
        edge = (mag_sat8 >> output_shift) & 0xFF

        valid_window = (row >= 2) and (col >= 2)
        results.append(edge if valid_window else 0)

        # ── sequential update (EXACT RTL match) ──
        linebuf2[col] = row1_col2
        linebuf1[col] = pixel_in

        if col == img_size - 1:
            col = 0

            # reset shift registers at row end (matches RTL!)
            r0_0 = r0_1 = 0
            r1_0 = r1_1 = 0
            r2_0 = r2_1 = 0

            if row == img_size - 1:
                row = 0
            else:
                row += 1

        else:
            col += 1

            # EXACT RTL shift behavior
            r0_0, r0_1 = r0_1, pixel_in
            r1_0, r1_1 = r1_1, row1_col2
            r2_0, r2_1 = r2_1, row2_col2

    return results


# ─────────────────────────────────────────────────────────────
# DUT helpers
# ─────────────────────────────────────────────────────────────
async def reset_dut(dut):
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)


async def run_frame(dut, image):
    results = []

    all_pixels = list(image) + [0x00]

    for i, pix in enumerate(all_pixels):
        dut.uio_in.value = int(pix) & 0xFF
        dut.ui_in.value  = 0x01

        await RisingEdge(dut.clk)

        if i > 0:
            results.append(int(dut.uo_out.value))

    dut.ui_in.value  = 0x00
    dut.uio_in.value = 0x00

    return results


async def check_frame(dut, image, label):
    expected = sobel_model(image)
    got      = await run_frame(dut, image)

    passed = True

    for idx, (exp, g) in enumerate(zip(expected, got)):
        row, col = divmod(idx, IMG_SIZE)

        if exp != g:
            dut._log.error(
                f"[{label}] FAIL ({row},{col}) pix={image[idx]:#04x} "
                f"expected={exp} got={g}"
            )
            passed = False

    return passed


# ─────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_all_zeros(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)
    assert await check_frame(dut, [0] * (IMG_SIZE * IMG_SIZE), "zeros")


@cocotb.test()
async def test_all_ones(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)
    assert await check_frame(dut, [255] * (IMG_SIZE * IMG_SIZE), "ones")


@cocotb.test()
async def test_vertical_edge(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)

    half = IMG_SIZE // 2
    image = [0 if c < half else 255
             for r in range(IMG_SIZE)
             for c in range(IMG_SIZE)]

    assert await check_frame(dut, image, "vertical")


@cocotb.test()
async def test_horizontal_edge(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)

    half = IMG_SIZE // 2
    image = [0 if r < half else 255
             for r in range(IMG_SIZE)
             for c in range(IMG_SIZE)]

    assert await check_frame(dut, image, "horizontal")


@cocotb.test()
async def test_checkerboard(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)

    image = [(255 if (r + c) % 2 == 0 else 0)
             for r in range(IMG_SIZE)
             for c in range(IMG_SIZE)]

    assert await check_frame(dut, image, "checker")


@cocotb.test()
async def test_two_frames(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)

    import random
    random.seed(42)

    N = IMG_SIZE * IMG_SIZE

    frame0 = [random.randint(0, 255) for _ in range(N)]
    frame1 = [random.randint(0, 255) for _ in range(N)]

    combined = frame0 + frame1

    expected = sobel_model(combined)

    got = await run_frame(dut, combined)

    assert expected == got, "test_two_frames FAILED"
