"""Paint original procedural energy plates for the combat effect atlas."""
from math import sin

from PIL import Image, ImageColor

from make_towers import CELL, ROOT, SIDE, Sprite, orbit

PALETTE = [
    "#8f66ff", "#a477ff", "#ffb727", "#ffc568", "#a75bfd", "#9ee7ff", "#9391dd",
    "#db93ff", "#74b6ff", "#f6caff", "#e598e4", "#f6f798", "#ff82d5", "#ff4873",
]


def soft(color, opacity):
    return (*color, opacity)


def spiral(sprite, arms, turns, outward):
    for arm in range(arms):
        angle = arm * 360 / arms
        for strand in range(4):
            points = []
            for i in range(48):
                progress = i / 47
                radius = (9 if outward else 20) + progress * (47 if outward else 33)
                points.append(orbit(radius, angle + (progress ** .74) * turns + strand * 4.1))
            for i in range(1, 48):
                envelope = sin(i / 48 * 3.1416) ** .65
                hue = sprite.lit if strand == 1 else sprite.tint
                opacity = round((150 if strand == 1 else 67) * envelope)
                sprite.line(points[i - 1:i + 1], soft(hue, opacity), 1 if strand > 0 else 2)
    for i in range(41):
        a = i * 137.508
        x, y = orbit(17 + (i * 13 % 40), a)
        sprite.circle(x, y, .6 + i % 3 * .24, soft(sprite.lit, 48 + (i * 17) % 87))


def mechanism(sprite, sides, rings):
    for j, radius in enumerate(rings):
        for i in range(sides):
            a = i * 360 / sides + (j % 2) * 180 / sides
            segment = 360 / sides
            sprite.arc(radius, a + 3, a + segment * .78, soft(sprite.tint, 84 + (j % 3) * 15), 1 if j else 2)
            sprite.line([orbit(radius - 4, a), orbit(radius + 2, a)], soft(sprite.lit, 180), 1)
    for i in range(sides):
        a = i * 360 / sides
        x, y = orbit(rings[-1] + 2, a)
        sprite.regular(4, 3, a, soft(sprite.lit, 150), x=x, y=y)


def flare(sprite, rays):
    for i in range(rays):
        angle = i * 360 / rays
        radius = 34 + (i * 17) % 26
        base = 21 + (i % 3) * 3
        poly = [orbit(base, angle - 8), orbit(radius, angle), orbit(base, angle + 7)]
        sprite.polygon(poly, soft(sprite.tint, 78 + i % 4 * 24))
        sprite.line([orbit(base + 1, angle), orbit(radius - 3, angle)], soft(sprite.lit, 150), 1)


def plate(index, sprite):
    if index == 0:
        spiral(sprite, 3, 195, True)
    elif index == 1:
        spiral(sprite, 3, 265, False)
        sprite.circle(0, 0, 14, "#080717", soft(sprite.lit, 206), 2)
        sprite.arc(17, -23, 165, soft(sprite.lit, 230), 2)
    elif index == 2:
        flare(sprite, 21)
        mechanism(sprite, 8, [17, 27, 37])
    elif index == 3:
        mechanism(sprite, 8, [20, 32, 44, 55])
        flare(sprite, 12)
        sprite.regular(4, 18, 45, soft(sprite.lit, 90), soft(sprite.lit, 210))
    elif index == 4:
        for y in range(-42, 45, 12):
            for x in range(-44, 49, 11):
                px = x + (y % 8)
                if px * px + y * y < 52 ** 2:
                    sprite.regular(6, 5.1, 15, soft(sprite.tint, 21 + abs(px * y) % 46), soft(sprite.lit, 25 + abs(px + y) % 43), 1, px, y)
    elif index == 5:
        for i in range(6):
            a = i * 60
            tip = orbit(56, a)
            sprite.polygon([orbit(18, a - 19), tip, orbit(19, a + 14)], soft(sprite.tint, 85), soft(sprite.lit, 199), 1)
            for j in [22, 33, 43]:
                sprite.line([orbit(j + 9, a - 11), orbit(j, a), orbit(j + 9, a + 11)], soft(sprite.lit, 179), 1)
        mechanism(sprite, 6, [12, 51])
    elif index == 6:
        mechanism(sprite, 6, [23, 35, 51])
        for i in range(8):
            a = i * 45
            sprite.line([orbit(56, a - 8), orbit(26, a), orbit(56, a + 8)], soft(sprite.lit, 105), 2)
    elif index == 7:
        mechanism(sprite, 12, [34, 40, 50, 54])
    elif index == 8:
        mechanism(sprite, 6, [16, 35, 49])
        for i in range(6):
            a = i * 60
            sprite.line([orbit(12, a), orbit(38, a - 14), orbit(31, a + 10), orbit(57, a + 1)], soft(sprite.lit, 155), 2)
    elif index in (9, 10, 11):
        colors = ["#ffadbb", "#ffcb84", "#ccf980", "#92f0fa", "#a7a8fa", "#f8a4f8"] if index == 9 else [sprite.tint] * 6
        mechanism(sprite, 6, [19, 46])
        for i in range(6):
            a = i * 60
            color = ImageColor.getrgb(colors[i]) if isinstance(colors[i], str) else colors[i]
            sprite.polygon([orbit(23, a - 23), orbit(47, a), orbit(23, a + 23), orbit(31, a)], soft(color, 95), soft(color, 197), 2)
        sprite.regular(3 if index == 10 else 6, 18, 0, soft(sprite.tint, 90), soft(sprite.lit, 195))
    elif index == 12:
        flare(sprite, 12)
        for i in range(8):
            a = i * 45
            x, y = orbit(39, a + 13)
            sprite.regular(4, 4, a, soft(sprite.lit, 170), x=x, y=y)
    elif index == 13:
        mechanism(sprite, 4, [17, 25, 39, 52])
        for a in range(0, 360, 90):
            sprite.polygon([orbit(23, a - 19), orbit(58, a - 5), orbit(57, a + 5), orbit(23, a + 16)], soft(sprite.tint, 94), soft(sprite.lit, 155))


def main():
    atlas = Image.new("RGBA", (CELL * SIDE, CELL * 2))
    for i, color in enumerate(PALETTE):
        sprite = Sprite(ImageColor.getrgb(color))
        plate(i, sprite)
        atlas.paste(sprite.render(), (i % SIDE * CELL, i // SIDE * CELL))
    atlas.save(ROOT / "attack_atlas.png", optimize=True)


if __name__ == "__main__":
    main()
