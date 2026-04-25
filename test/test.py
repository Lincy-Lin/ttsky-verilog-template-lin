# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

# ── Parameters ────────────────────────────────────────────────────────────────
IMG_SIZE     = 6
OUTPUT_BITS  = 8
OUTPUT_SHIFT = 8 - OUTPUT_BITS   # = 0

# ── Software model ────────────────────────────────────────────────────────────
def sobel_model(image, img_size=IMG_SIZE, output_bits=OUTPUT_BITS):
    """
    Cycle-accurate Python model of the RTL.

    Key insight: In the RTL always block, valid_window / edge_quantized are
    evaluated using the CURRENT (pre-update) values of row and col, because
    non-blocking assignments update row/col only at the END of the time step.
    This model reproduces that behaviour exactly.

    image: flat list of img_size*img_size uint8 values, row-major.
    Returns: list of img_size*img_size output values in the same order.
    """
    output_shift = 8 - output_bits

    linebuf1 = [0] * img_size
    linebuf2 = [0] * img_size
    r0_0 = r0_1 = 0
    r1_0 = r1_1 = 0
    r2_0 = r2_1 = 0
    row = 0
    col = 0

    results = []

    for idx in range(img_size * img_size):
        pixel_in = image[idx]

        # --- Combinational (evaluated with current row/col) ---
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

        abs_gx = abs(gx) & 0xFFF
        abs_gy = abs(gy) & 0xFFF
        mag     = (abs_gx + abs_gy) & 0x1FFF
        mag_sat8 = 0xFF if mag > 255 else mag
        edge    = (mag_sat8 >> output_shift) & 0xFF

        # valid_window uses pre-update row/col (non-blocking assignment semantics)
        valid_window = (row >= 2) and (col >= 2)
        results.append(edge if valid_window else 0)

        # --- Sequential update (mirrors non-blocking assignments) ---
        linebuf2[col] = row1_col2
        linebuf1[col] = pixel_in

        if col == img_size - 1:
            col = 0
            r0_0 = r0_1 = 0
            r1_0 = r1_1 = 0
            r2_0 = r2_1 = 0
            row = 0 if row == img_size - 1 else row + 1
        else:
            col += 1
            r2_0, r2_1 = r2_1, pixel_in
            r1_0, r1_1 = r1_1, row1_col2
            r0_0, r0_1 = r0_1, row2_col2

    return results


# ── DUT helpers ───────────────────────────────────────────────────────────────
async def reset_dut(dut):
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)


async def run_frame(dut, image):
    """
    Send a full frame and collect registered outputs.

    RTL timing: out is a registered output (non-blocking assignment).
    The value written on clock edge N is only readable AFTER edge N settles.
    In cocotb this means: drive pixel N before edge N+1, then read out
    (which now holds pixel N-1 result). Collect with 1-cycle offset and
    flush one extra cycle at the end.
    """
    results = []
    for i, pix in enumerate(image):
        dut.uio_in.value = int(pix) & 0xFF
        dut.ui_in.value  = 0x01
        await RisingEdge(dut.clk)
        if i > 0:
            results.append(int(dut.uo_out.value))  # result for pixel i-1
    # flush: one more edge to read the last pixel output
    dut.ui_in.value  = 0x00
    dut.uio_in.value = 0x00
    await RisingEdge(dut.clk)
    results.append(int(dut.uo_out.value))
    return results


async def check_frame(dut, image, label):
    expected = sobel_model(image)
    got      = await run_frame(dut, image)
    passed   = True
    for idx, (exp, g) in enumerate(zip(expected, got)):
        row, col = divmod(idx, IMG_SIZE)
        if exp != g:
            dut._log.error(
                f"[{label}] FAIL ({row},{col}) pix={image[idx]:#04x} "
                f"expected={exp} got={g}"
            )
            passed = False
        else:
            dut._log.debug(
                f"[{label}] OK   ({row},{col}) pix={image[idx]:#04x} out={g}"
            )
    return passed


# ── Test 1: all-zero image ────────────────────────────────────────────────────
@cocotb.test()
async def test_all_zeros(dut):
    """Flat black image → Sobel gradient everywhere = 0."""
    dut._log.info("test_all_zeros")
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)
    ok = await check_frame(dut, [0] * (IMG_SIZE * IMG_SIZE), "all_zeros")
    assert ok, "test_all_zeros FAILED"
    dut._log.info("test_all_zeros PASSED")


# ── Test 2: all-255 image ─────────────────────────────────────────────────────
@cocotb.test()
async def test_all_ones(dut):
    """Flat white image → gradient = 0."""
    dut._log.info("test_all_ones")
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)
    ok = await check_frame(dut, [255] * (IMG_SIZE * IMG_SIZE), "all_ones")
    assert ok, "test_all_ones FAILED"
    dut._log.info("test_all_ones PASSED")


# ── Test 3: vertical edge ─────────────────────────────────────────────────────
@cocotb.test()
async def test_vertical_edge(dut):
    """Left half=0, right half=255 → strong Gx."""
    dut._log.info("test_vertical_edge")
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)
    half  = IMG_SIZE // 2
    image = [0 if c < half else 255
             for r in range(IMG_SIZE) for c in range(IMG_SIZE)]
    ok = await check_frame(dut, image, "vertical_edge")
    assert ok, "test_vertical_edge FAILED"
    dut._log.info("test_vertical_edge PASSED")


# ── Test 4: horizontal edge ───────────────────────────────────────────────────
@cocotb.test()
async def test_horizontal_edge(dut):
    """Top half=0, bottom half=255 → strong Gy."""
    dut._log.info("test_horizontal_edge")
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)
    half  = IMG_SIZE // 2
    image = [0 if r < half else 255
             for r in range(IMG_SIZE) for c in range(IMG_SIZE)]
    ok = await check_frame(dut, image, "horizontal_edge")
    assert ok, "test_horizontal_edge FAILED"
    dut._log.info("test_horizontal_edge PASSED")


# ── Test 5: checkerboard ──────────────────────────────────────────────────────
@cocotb.test()
async def test_checkerboard(dut):
    """Checkerboard → high gradient in valid window."""
    dut._log.info("test_checkerboard")
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)
    image = [255 if (r + c) % 2 == 0 else 0
             for r in range(IMG_SIZE) for c in range(IMG_SIZE)]
    ok = await check_frame(dut, image, "checkerboard")
    assert ok, "test_checkerboard FAILED"
    dut._log.info("test_checkerboard PASSED")


# ── Test 6: two consecutive frames ───────────────────────────────────────────
@cocotb.test()
async def test_two_frames(dut):
    """Two full frames back-to-back; RTL auto-wraps row/col."""
    dut._log.info("test_two_frames")
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    await reset_dut(dut)

    import random
    random.seed(42)

    all_ok = True
    for frame in range(2):
        image = [random.randint(0, 255) for _ in range(IMG_SIZE * IMG_SIZE)]
        dut._log.info(f"  Frame {frame}")
        ok = await check_frame(dut, image, f"frame{frame}")
        all_ok = all_ok and ok

    assert all_ok, "test_two_frames FAILED"
    dut._log.info("test_two_frames PASSED")
