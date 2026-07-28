import os
import struct

SIZE = 32
RADIUS = 16


def write_tga(path, pixels, size):
    # Uncompressed 32-bit BGRA TGA, origin bottom-left (standard TGA order).
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,  # id length
        0,  # color map type
        2,  # image type: uncompressed true-color
        0, 0, 0,  # color map spec
        0, 0,  # x, y origin
        size, size,
        32,  # bits per pixel
        8,  # image descriptor: 8 bits alpha
    )
    with open(path, "wb") as f:
        f.write(header)
        for y in range(size - 1, -1, -1):
            for x in range(size):
                a = pixels[y][x]
                f.write(struct.pack("<BBBB", 255, 255, 255, a))  # B,G,R,A (white)


def rounded_rect_alpha(round_left, round_right):
    px = [[0 for _ in range(SIZE)] for _ in range(SIZE)]
    r = RADIUS
    for y in range(SIZE):
        for x in range(SIZE):
            inside = True

            def corner_dist(cx, cy):
                return ((x - cx + 0.5) ** 2 + (y - cy + 0.5) ** 2) ** 0.5

            if round_left and x < r and y < r:
                inside = corner_dist(r, r) <= r
            elif round_left and x < r and y >= SIZE - r:
                inside = corner_dist(r, SIZE - r) <= r
            elif round_right and x >= SIZE - r and y < r:
                inside = corner_dist(SIZE - r, r) <= r
            elif round_right and x >= SIZE - r and y >= SIZE - r:
                inside = corner_dist(SIZE - r, SIZE - r) <= r

            px[y][x] = 255 if inside else 0
    return px


variants = {
    "RoundMaskPill.tga": (True, True),
    "RoundMaskLeft.tga": (True, False),
    "RoundMaskRight.tga": (False, True),
    "RoundMaskSquare.tga": (False, False),
}

out_dir = os.path.dirname(os.path.abspath(__file__))

for filename, (left, right) in variants.items():
    pixels = rounded_rect_alpha(left, right)
    write_tga(os.path.join(out_dir, filename), pixels, SIZE)
    print("wrote", filename)
