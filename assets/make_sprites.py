"""Generate the original linear-alpha sprite masks. Requires Pillow."""
from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 96
CENTER = SIZE // 2
HERE = Path(__file__).parent


def glow(radius, opacity):
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            distance = ((x - CENTER) ** 2 + (y - CENTER) ** 2) ** 0.5
            alpha = round(opacity * max(0.0, 1.0 - distance / radius) ** 1.7)
            pixels[x, y] = (166, 166, 166, alpha)
    return image


def at(points):
    return [(CENTER + x, CENTER + y) for x, y in points]


def tone(gray, alpha=255):
    return (gray, gray, gray, alpha)


def layer(image):
    foreground = Image.new("RGBA", image.size)
    return foreground, ImageDraw.Draw(foreground)


def save(image, foreground, name):
    Image.alpha_composite(image, foreground).save(HERE / (name + ".png"))


image = glow(37, 148)
shape, pen = layer(image)
pen.polygon(at([(-36, 0), (-16, -5), (0, -7), (0, 7), (-16, 5)]), fill=tone(140, 85))
hull = at([(23, 0), (0, -16), (-20, 0), (0, 16)])
pen.polygon(hull, fill=tone(65), outline=tone(223), width=3)
pen.line(at([(-9, 0), (12, 0)]), fill=tone(155), width=4)
pen.polygon(at([(10, 0), (3, -6), (-4, 0), (3, 6)]), fill=tone(253))
save(image, shape, "drone")

image = glow(47, 116)
shape, pen = layer(image)
hexagon = at([(32 * cos(pi / 6 + i * pi / 3), 32 * sin(pi / 6 + i * pi / 3)) for i in range(6)])
pen.polygon(hexagon, fill=tone(56), outline=tone(178), width=3)
pen.ellipse((28, 28, 68, 68), outline=tone(128), width=2)
save(image, shape, "turret_base")

image = glow(25, 116)
shape, pen = layer(image)
pen.rounded_rectangle((42, 41, 83, 55), radius=5, fill=tone(160))
pen.line((53, 48, 82, 48), fill=tone(241), width=4)
pen.ellipse((34, 34, 62, 62), fill=tone(195))
pen.ellipse((42, 42, 54, 54), fill=tone(253))
save(image, shape, "turret_head")

image = glow(27, 128)
shape, pen = layer(image)
pen.polygon(at([(-47, 0), (-12, -8), (5, -5), (5, 5), (-12, 8)]), fill=tone(155, 116))
pen.rounded_rectangle((20, 45, 52, 51), radius=3, fill=tone(222))
pen.ellipse((42, 42, 54, 54), fill=tone(253))
save(image, shape, "bolt")

image = Image.new("RGBA", (SIZE, SIZE))
shape, pen = layer(image)
pen.ellipse((3, 3, 92, 92), outline=tone(198, 80), width=7)
pen.ellipse((4, 4, 91, 91), outline=tone(246, 213), width=2)
save(image, shape, "shockwave")
