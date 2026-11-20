"""Bake the monochrome sprite masks tinted by the game's canvas shader."""
from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 192
CENTER = SIZE // 2
DEST = Path(__file__).parent / "mobs"


def tone(level, alpha=255):
    return (level, level, level, alpha)


def polygon(points, fill=52, rim=212, width=4):
    points = [(x + CENTER, y + CENTER) for x, y in points]
    draw.polygon(points, fill=tone(fill))
    draw.line(points + [points[0]], fill=tone(rim), width=width, joint="curve")


def regular(sides, radius, angle=0.0, center=(0, 0)):
    return [(center[0] + radius * cos(angle + i * 2 * pi / sides),
             center[1] + radius * sin(angle + i * 2 * pi / sides))
            for i in range(sides)]


def ring(radius, thickness=4, gray=202, alpha=255):
    pad = CENTER - radius
    draw.ellipse((pad, pad, SIZE - pad, SIZE - pad), outline=tone(gray, alpha), width=thickness)


def core(x=0, y=0, radius=12, sides=4):
    polygon(regular(sides, radius, 0, (x, y)), 252, 226, 2)


def ray(points, gray=178, width=4):
    draw.line([(x + CENTER, y + CENTER) for x, y in points], fill=tone(gray), width=width)


def dart():
    polygon([(66, 0), (-45, -36), (-25, 0), (-45, 36)], 67)
    ray([(-20, 0), (49, 0)], 138, 8)
    core(18, 0, 12)


def hex_shell():
    polygon(regular(6, 56), 42, 202, 7)
    polygon(regular(6, 38), 77, 152, 3)
    ray([(-45, -22), (-8, -13), (41, -18)], 125)
    ray([(-45, 22), (-8, 13), (41, 18)], 125)
    core(12, 0, 14)


def swarm():
    polygon([(57, 0), (0, -37), (-38, -28), (-31, 28), (0, 37)], 88)
    for dy in [-17, 17]:
        core(3, dy, 12, 3)


def cell():
    for angle in [0, 2 * pi / 3, 4 * pi / 3]:
        center = (29 * cos(angle), 29 * sin(angle))
        polygon(regular(6, 27, angle, center), 71, 174)
    ring(33, 4, 160)
    core(0, 0, 16, 6)


def split():
    polygon(regular(4, 63), 53, 182, 5)
    for angle in [0, pi / 2, pi, 3 * pi / 2]:
        center = (27 * cos(angle), 27 * sin(angle))
        polygon(regular(4, 16, angle, center), 194, 234, 2)
    core(0, 0, 11)


def conductor():
    ring(65, 5)
    ring(48, 7, 158)
    polygon(regular(8, 35, pi / 8), 56, 194)
    core(radius=19, sides=8)


def guardian():
    polygon([(60, -36), (42, 0), (60, 36), (0, 57), (-53, 30), (-53, -30), (0, -57)], 65, 228, 5)
    polygon(regular(6, 36), 94)
    ray([(-16, 0), (26, 0)], 250, 8)
    ray([(4, -20), (4, 20)], 250, 8)


def relay():
    polygon(regular(3, 67, 0), 42)
    ring(33, 4)
    for angle in [0, 2 * pi / 3, 4 * pi / 3]:
        core(38 * cos(angle), 38 * sin(angle), 10)
    core(radius=13)


def tank():
    polygon([(-61, -44), (43, -44), (65, -24), (65, 24), (43, 44), (-61, 44)], 48, 214, 6)
    for y in [-27, 27]:
        ray([(-48, y), (45, y)], 134, 12)
        ray([(-39, y + 2), (38, y + 2)], 188, 3)
    polygon(regular(6, 36), 98)
    core(12, 0, 12, 6)


def calamity():
    polygon(regular(10, 65), 53, 225, 6)
    ring(49, 5, 174)
    for i in range(4):
        a = i * pi / 2
        core(37 * cos(a), 37 * sin(a), 13)
    core(radius=23, sides=6)


def boss():
    polygon([(74, 0), (54, -42), (13, -66), (-25, -63), (-68, -33), (-56, 0),
             (-68, 33), (-25, 63), (13, 66), (54, 42)], 48, 218, 7)
    ring(72, 3, 146, 210)
    polygon(regular(8, 47, pi / 8), 94, 207)
    for a in [pi / 3, pi, 5 * pi / 3]:
        core(47 * cos(a), 47 * sin(a), 13)
    ring(28, 4)
    core(7, 0, 20, 6)


DEST.mkdir(exist_ok=True)
variants = {
    "dart": dart, "hex": hex_shell, "swarm": swarm, "cell": cell, "split": split,
    "ring": conductor, "guardian": guardian, "relay": relay, "tank": tank,
    "calamity": calamity, "boss": boss,
}
for name, paint in variants.items():
    canvas = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(canvas)
    paint()
    canvas.resize((96, 96), Image.Resampling.LANCZOS).save(DEST / f"{name}.png")
