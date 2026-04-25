# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

# ── Parameters (must match Verilog) ──────────────────────────────────────────
IMG_SIZE     = 6
OUTPUT_BITS  = 8
OUTPUT_SHIFT = 8 - OUTPUT_BITS   # = 0

# ── Software model ────────────────────────────────────────────────────────────
def sobel_model(image, img_size=IMG_SIZE, output_bits=OUTPUT_BITS):
    """
    Pure-Python Sobel model that mirrors the RTL exactly.
    image: list of img_size*img_size uint8 values, row-major.
    Returns: list of img_size*img_size output values (same order).
    """
    output_shift = 8 - output_bits
    results = []
    # Two line buffers, initialised to 0
    linebuf1 = [0] * img_size
    linebuf2 = [0] * img_size
    # Six pipeline registers (two per row of the 3×3 window)
    r0_0 = r0_1 = 0   # current row,  two cycles ago / one cycle ago
    r1_0 = r1_1 = 0   # row-1
    r2_0 = r2_1 = 0   # row-2

    for row in range(img_size):
        for col in range(img_size):
            pixel_in = image[row * img_size + col]

            # Read from line buffers BEFORE writing (non-blocking semantics)
            row1_col2 = linebuf1[col]
            row2_col2 = linebuf2[col]

            # Build the 3×3 window
            p00, p01, p02 = r2_0, r2_1, row2_col2
            p10, p11, p12 = r1_0, r1_1, row1_col2
            p20, p21, p22 = r0_0, r0_1, pixel_in

            # Sobel kernels (no multiply, just shift+add)
            gx = (-p00 + p02 - 2*p10 + 2*p12 - p20 + p22)
            gy = ( p00 + 2*p01 + p02 - p20 - 2*p21 - p22)

            # Clip to 12-bit signed range the RTL would produce
            def clip12s(v):
                v &= 0xFFF
                return v - 0x1000 if v >= 0x800 else v

            gx = clip12s(gx)
            gy = clip12s(gy)

            abs_gx = abs(gx) & 0xFFF
            abs_gy = abs(gy) & 0xFFF
            mag = (abs_gx + abs_gy) & 0x1FFF          # 13-bit
            mag_sat8 = 0xFF if mag > 255 else mag
            edge = (mag_sat8 >> output_shift) & 0xFF

            valid_window = (row >= 2) and (col >= 2)
            results.append(edge if valid_window else 0)

            # Update line buffers
            linebuf2[col] = row1_col2
            linebuf1[col] = pixel_in

            # Update shift registers
            if col == img_size - 1:
                r0_0 = r0_1 = 0
                r1_0 = r1_1 = 0
                r2_0 = r2_1 = 0
            else:
                r2_0, r2_1 = r2_1, pixel_in
                r1_0, r1_1 = r1_1, row1_col2
                r0_0, r0_1 = r0_1, row2_col2

    return results


# ── Helper: send one pixel and read back output ───────────────────────────────
async def send_pixel(dut, pixel: int):
    """Assert pixel_valid for one clock cycle with the given pixel value."""
    dut.uio_in.value = pixel & 0xFF
    dut.ui_in.value  = 0x01          # ui_in[0] = pixel_valid
    await RisingEdge(dut.clk)
    dut.ui_in.value  = 0x00          # de-assert valid
    # Output is registered, available one cycle after the rising edge
    # (already captured on the edge we just passed)
    return int(dut.uo_out.value)


async def reset_dut(dut):
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)


# ── Test 1: all-zero image → all outputs must be 0 ───────────────────────────
@cocotb.test()
async def test_all_zeros(dut):
    """Flat image → Sobel gradient everywhere = 0."""
    dut._log.info("test_all_zeros: start")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    image = [0] * (IMG_SIZE * IMG_SIZE)
    expected = sobel_model(image)

    for idx, pix in enumerate(image):
        got = await send_pixel(dut, pix)
        row, col = divmod(idx, IMG_SIZE)
        exp = expected[idx]
        dut._log.info(f"  pixel ({row},{col}) pix={pix:#04x} exp={exp} got={got}")
        assert got == exp, f"FAIL at ({row},{col}): expected {exp}, got {got}"

    dut._log.info("test_all_zeros: PASS")


# ── Test 2: all-255 image → all outputs must be 0 ────────────────────────────
@cocotb.test()
async def test_all_ones(dut):
    """Uniform bright image → gradient = 0."""
    dut._log.info("test_all_ones: start")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    image = [255] * (IMG_SIZE * IMG_SIZE)
    expected = sobel_model(image)

    for idx, pix in enumerate(image):
        got = await send_pixel(dut, pix)
        row, col = divmod(idx, IMG_SIZE)
        exp = expected[idx]
        assert got == exp, f"FAIL at ({row},{col}): expected {exp}, got {got}"

    dut._log.info("test_all_ones: PASS")


# ── Test 3: vertical edge (left half=0, right half=255) ──────────────────────
@cocotb.test()
async def test_vertical_edge(dut):
    """
    Left half black, right half white → strong Gx, weak Gy.
    Only checks that RTL matches software model (not absolute values).
    """
    dut._log.info("test_vertical_edge: start")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    half = IMG_SIZE // 2
    image = []
    for r in range(IMG_SIZE):
        for c in range(IMG_SIZE):
            image.append(0 if c < half else 255)

    expected = sobel_model(image)

    for idx, pix in enumerate(image):
        got = await send_pixel(dut, pix)
        row, col = divmod(idx, IMG_SIZE)
        exp = expected[idx]
        dut._log.info(f"  pixel ({row},{col}) pix={pix:#04x} exp={exp} got={got}")
        assert got == exp, f"FAIL at ({row},{col}): expected {exp}, got {got}"

    dut._log.info("test_vertical_edge: PASS")


# ── Test 4: horizontal edge (top half=0, bottom half=255) ────────────────────
@cocotb.test()
async def test_horizontal_edge(dut):
    """Top half black, bottom half white → strong Gy."""
    dut._log.info("test_horizontal_edge: start")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    half = IMG_SIZE // 2
    image = []
    for r in range(IMG_SIZE):
        for c in range(IMG_SIZE):
            image.append(0 if r < half else 255)

    expected = sobel_model(image)

    for idx, pix in enumerate(image):
        got = await send_pixel(dut, pix)
        row, col = divmod(idx, IMG_SIZE)
        exp = expected[idx]
        dut._log.info(f"  pixel ({row},{col}) pix={pix:#04x} exp={exp} got={got}")
        assert got == exp, f"FAIL at ({row},{col}): expected {exp}, got {got}"

    dut._log.info("test_horizontal_edge: PASS")


# ── Test 5: checkerboard pattern ─────────────────────────────────────────────
@cocotb.test()
async def test_checkerboard(dut):
    """Checkerboard → high gradient everywhere in valid window."""
    dut._log.info("test_checkerboard: start")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    image = []
    for r in range(IMG_SIZE):
        for c in range(IMG_SIZE):
            image.append(255 if (r + c) % 2 == 0 else 0)

    expected = sobel_model(image)

    for idx, pix in enumerate(image):
        got = await send_pixel(dut, pix)
        row, col = divmod(idx, IMG_SIZE)
        exp = expected[idx]
        dut._log.info(f"  pixel ({row},{col}) pix={pix:#04x} exp={exp} got={got}")
        assert got == exp, f"FAIL at ({row},{col}): expected {exp}, got {got}"

    dut._log.info("test_checkerboard: PASS")


# ── Test 6: two consecutive frames (reset between frames via row/col wrap) ───
@cocotb.test()
async def test_two_frames(dut):
    """Send two full frames back-to-back; RTL auto-wraps row/col."""
    dut._log.info("test_two_frames: start")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    import random
    random.seed(42)

    for frame in range(2):
        image = [random.randint(0, 255) for _ in range(IMG_SIZE * IMG_SIZE)]
        expected = sobel_model(image)
        dut._log.info(f"  Frame {frame}")

        for idx, pix in enumerate(image):
            got = await send_pixel(dut, pix)
            row, col = divmod(idx, IMG_SIZE)
            exp = expected[idx]
            assert got == exp, (
                f"Frame {frame} FAIL at ({row},{col}): expected {exp}, got {got}"
            )

    dut._log.info("test_two_frames: PASS")
