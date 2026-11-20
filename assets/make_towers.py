"""Paint the 30 original tower chassis and rotating weapon heads. Requires Pillow."""
import json
from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageColor, ImageDraw

ROOT = Path(__file__).resolve().parent
CELL = 128
SIDE = 8
SCALE = 2
BASES = [
    (6, 31, 30), (8, 29, 22), (4, 33, 45), (6, 32, 0), (6, 31, 30),
    (3, 34, 0), (8, 35, 22), (6, 36, 0), (4, 34, 45), (3, 35, 30),
    (6, 35, 30), (8, 37, 22), (4, 39, 45), (8, 38, 22), (6, 38, 30),
    (5, 37, -18), (6, 38, 0), (6, 40, 30), (3, 41, 0), (3, 41, 30),
    (5, 41, 18), (8, 40, 22), (4, 41, 45), (6, 43, 0), (6, 43, 30),
    (4, 43, 45), (3, 44, 30), (8, 47, 22), (6, 47, 0), (4, 47, 45),
]


def blend(a, b, mix):
    return tuple(round(x + (y - x) * mix) for x, y in zip(a, b))


def orbit(radius, angle):
    angle *= pi / 180
    return (cos(angle) * radius, sin(angle) * radius)


class Sprite:
    def __init__(self, tint):
        self.image = Image.new("RGBA", (CELL * SCALE, CELL * SCALE))
        self.pen = ImageDraw.Draw(self.image)
        self.tint = tint
        self.lit = blend(tint, (255, 249, 228), 0.56)
        self.steel = blend((72, 83, 90), tint, 0.20)
        self.rim = blend((157, 166, 169), tint, 0.33)

    def xy(self, point):
        return tuple(round((axis + CELL / 2) * SCALE) for axis in point)

    def polygon(self, points, fill, edge=None, width=2):
        self.pen.polygon([self.xy(p) for p in points], fill=fill, outline=edge, width=width * SCALE)

    def line(self, points, color, width=2):
        self.pen.line([self.xy(p) for p in points], fill=color, width=width * SCALE, joint="curve")

    def circle(self, x, y, radius, fill=None, edge=None, width=2):
        self.pen.ellipse([self.xy((x - radius, y - radius)), self.xy((x + radius, y + radius))],
                         fill=fill, outline=edge, width=width * SCALE)

    def arc(self, radius, start, end, color, width=2):
        self.pen.arc([self.xy((-radius, -radius)), self.xy((radius, radius))],
                     start, end, color, width * SCALE)

    def regular(self, sides, radius, phase, fill, edge=None, width=2, x=0, y=0):
        points = [orbit(radius, phase + i * 360 / sides) for i in range(sides)]
        self.polygon([(a + x, b + y) for a, b in points], fill, edge, width)

    def chassis(self, number, sides, radius, phase):
        self.regular(sides, radius + 2, phase, "#111419", "#101216")
        self.regular(sides, radius, phase, "#1d232a", self.rim, 2)
        self.regular(sides, radius - 5, phase, self.steel, "#2c323a", 2)
        self.regular(sides, radius - 12, phase, "#242a30", "#13191e", 2)
        for i in range(sides):
            angle = phase + i * 360 / sides
            x, y = orbit(radius - 6, angle)
            self.circle(x, y, 2 if number < 13 else 2.5, self.rim, "#171b21", 1)
        for angle in range(45, 361, 90):
            self.arc(radius - 2, angle - 12, angle + 12, self.tint, 2 if number < 21 else 3)
        if number >= 28:
            for angle in range(0, 360, 60):
                self.arc(54, angle + 5, angle + 42, self.tint, 2)

    def armor(self, points):
        self.polygon(points, self.steel, self.rim, 2)
        self.line(points[:2], self.lit, 2)

    def barrel(self, x, end, y, width):
        self.armor([(x, y - width), (end - 6, y - width),
                    (end, y - width / 2), (end, y + width / 2),
                    (end - 6, y + width), (x, y + width)])
        self.line([(x + 4, y), (end - 4, y)], self.tint, max(2, round(width / 3)))
        self.line([(end - 4, y - width / 2), (end - 4, y + width / 2)], self.lit, 3)

    def gem(self, x, y, r, sides=4):
        self.regular(sides, r + 3, 0, "#23242a", self.rim, 2, x, y)
        self.regular(sides, r, 0, self.tint, self.lit, 2, x, y)
        self.polygon([(x, y), (x, y - r * .78), (x + r * .76, y)], self.lit)

    def nodes(self, count, radius, size, phase=0):
        for i in range(count):
            x, y = orbit(radius, i * 360 / count + phase)
            a, b = orbit(radius * 0.46, i * 360 / count + phase)
            self.line([(a, b), (x, y)], self.steel, 5)
            self.circle(x, y, size + 3, self.steel, self.rim, 2)
            self.circle(x, y, size, self.tint, self.lit, 2)

    def jaws(self, gap, end, width):
        for sign in [-1, 1]:
            self.armor([(-13, sign * gap), (end - 8, sign * (gap + width)),
                        (end, sign * (gap + 3)), (end - 3, sign * gap),
                        (1, sign * (gap - 4))])
            self.line([(2, sign * gap), (end - 4, sign * (gap + 1))], self.tint, 3)

    def head(self, number):
        match number:
            case 1:  # Single round turret and short gun.
                self.barrel(-4, 39, 0, 6)
                self.circle(-5, 0, 17, self.steel, self.rim, 3)
                self.circle(-5, 0, 6, self.tint, self.lit)
            case 2:  # Two lightweight automatic guns.
                for y in [-9, 9]:
                    self.barrel(-10, 41, y, 5)
                self.armor([(-23, -15), (1, -15), (13, 0), (1, 15), (-23, 15)])
                self.gem(-8, 0, 5, 6)
            case 3:  # Armored penetrator with a ribbed long barrel.
                self.barrel(-12, 47, 0, 9)
                self.armor([(-24, -18), (13, -18), (23, -10), (17, 14), (-24, 18)])
                for x in [-8, 0, 8]:
                    self.line([(x, -13), (x + 3, 13)], self.tint, 3)
            case 4:  # Three wide-mouthed dispersal chambers.
                self.armor([(-24, -17), (22, -27), (35, -20), (35, 20), (22, 27), (-24, 17)])
                for y in [-15, 0, 15]:
                    self.barrel(-4, 40 if y == 0 else 35, y, 6)
                self.gem(-13, 0, 7)
            case 5:  # Cryogenic tubes, a frosted reservoir and fork.
                self.barrel(7, 42, 0, 5)
                for y in [-13, 13]:
                    self.circle(-8, y, 10, self.steel, self.rim)
                    self.line([(-15, y), (7, y), (22, y * .54)], self.tint, 4)
                self.gem(-2, 0, 10, 6)
            case 6:  # Three Tesla electrodes.
                self.nodes(3, 24, 7, 0)
                self.gem(0, 0, 10, 6)
            case 7:  # Stubby mortar bell with visible bore.
                self.armor([(-25, -18), (12, -18), (27, -11), (27, 11), (12, 18), (-25, 18)])
                self.circle(13, 0, 19, self.steel, self.rim, 3)
                self.circle(13, 0, 11, "#222329", self.tint, 3)
                self.circle(13, 0, 5, "#141419")
            case 8:  # Pilot flame and twin fuel tanks.
                self.jaws(8, 31, 9)
                for y in [-15, 15]:
                    self.circle(-15, y, 11, self.steel, self.rim, 2)
                    self.circle(-15, y, 5, self.tint)
                self.polygon([(0, -6), (31, -4), (43, 0), (31, 4), (0, 6)], self.tint, self.lit)
            case 9:  # Long thin precision barrel and offset scope.
                self.barrel(-21, 52, 0, 5)
                self.armor([(-31, -11), (-8, -11), (5, 0), (-8, 11), (-31, 11)])
                self.barrel(-14, 18, -14, 6)
                self.circle(12, -14, 4, self.lit)
            case 10:  # Open targeting dish and reticle.
                self.arc(27, -79, 79, self.rim, 8)
                self.arc(26, -68, 68, self.tint, 3)
                self.armor([(-24, -17), (6, -9), (10, 9), (-24, 17)])
                self.line([(-4, 0), (34, 0)], self.tint, 3)
                self.circle(23, 0, 7, "#20232b", self.lit, 2)
            case 11:  # Long optical cavity.
                self.jaws(11, 40, 5)
                self.gem(-7, 0, 13, 6)
                for x in [12, 24, 36]:
                    self.line([(x, -6), (x, 6)], self.lit, 3)
            case 12:  # Armored pods, each loaded with clustered missiles.
                for y in [-14, 14]:
                    self.armor([(-25, y - 11), (19, y - 11), (29, y - 5),
                                (29, y + 9), (-25, y + 9)])
                    for x in [-13, 1, 15]:
                        self.circle(x, y, 4, "#21232a", self.tint, 2)
                self.gem(-18, 0, 5)
            case 13:  # Long twin rails and charged accelerators.
                self.jaws(10, 54, 11)
                self.gem(-13, 0, 13, 4)
                for x in [6, 18, 30, 42]:
                    self.line([(x, -13), (x, -7)], self.lit, 4)
                    self.line([(x, 7), (x, 13)], self.lit, 4)
            case 14:  # Four containment coils surrounding a plasma sphere.
                self.nodes(4, 28, 7, 45)
                self.circle(0, 0, 20, "#30233b", self.tint, 3)
                self.circle(0, 0, 11, self.tint, self.lit, 4)
                self.circle(-4, -3, 4, self.lit)
            case 15:  # Six irregular ice fins.
                for a in range(0, 360, 60):
                    self.polygon([orbit(12, a - 20), orbit(26, a - 14), orbit(39, a),
                                  orbit(22, a + 16), orbit(12, a + 12)], self.tint, self.rim)
                    self.line([orbit(17, a), orbit(36, a)], self.lit, 3)
                self.gem(0, 0, 13, 6)
            case 16:  # Five separated launch crystals.
                for a in [-68, -34, 0, 34, 68]:
                    x, y = orbit(28 if a else 39, a)
                    self.line([(-5, 0), (x, y)], self.steel, 7)
                    self.gem(x, y, 7 if a else 10)
                self.gem(-12, 0, 11, 5)
            case 17:  # Two back-swept return rails.
                for sign in [-1, 1]:
                    self.armor([(-34, sign * 21), (-5, sign * 27), (37, sign * 11),
                                (17, sign * 7), (-12, sign * 16)])
                    self.line([(-24, sign * 21), (-7, sign * 20), (23, sign * 11)], self.tint, 3)
                self.gem(0, 0, 12, 6)
            case 18:  # Satellite uplink dish and feed arms.
                self.circle(0, 0, 25, self.steel, self.rim, 4)
                self.arc(20, 20, 270, self.tint, 2)
                self.arc(28, -75, 75, self.lit, 4)
                self.line([(-13, -15), (21, 0), (-11, 16)], self.rim, 4)
                self.gem(18, 0, 8)
            case 19:  # A large prism fed by three smaller lenses.
                self.nodes(3, 29, 6, 180)
                self.gem(5, 0, 22, 3)
                self.line([(5, 0), (34, 12)], self.lit, 3)
            case 20:  # Three massive magnets orbiting a void.
                for a in [0, 120, 240]:
                    self.arc(30, a + 9, a + 91, self.rim, 9)
                    self.arc(26, a + 14, a + 84, self.tint, 3)
                self.circle(0, 0, 16, "#141319", self.tint, 3)
                self.arc(10, 200, 340, self.lit, 2)
            case 21:  # Five sweeping impeller blades.
                for a in range(0, 360, 72):
                    self.polygon([orbit(11, a), orbit(24, a - 31), orbit(39, a - 15),
                                  orbit(29, a + 18), orbit(14, a + 25)], self.steel, self.rim)
                    self.line([orbit(15, a + 11), orbit(27, a - 3), orbit(36, a - 13)], self.tint, 4)
                self.gem(0, 0, 11, 5)
            case 22:  # Coaxial shockwave emitter.
                self.circle(0, 0, 33, self.steel, self.rim, 3)
                for r in [11, 18, 25]:
                    self.circle(0, 0, r, None, self.tint if r != 18 else self.lit, 3)
                for a in [45, 135, 225, 315]:
                    self.arc(34, a - 14, a + 14, self.lit, 5)
                self.circle(0, 0, 5, self.lit)
            case 23:  # Four lightning pylons and branching bus bars.
                self.nodes(4, 30, 8, 0)
                self.regular(4, 20, 45, self.steel, self.rim, 3)
                self.line([(-19, 3), (-5, -11), (-2, 3), (7, -3), (4, 12), (22, -3)], self.lit, 4)
            case 24:  # A caged star.
                for a in range(0, 360, 60):
                    self.arc(37, a + 4, a + 48, self.rim, 7)
                    self.line([orbit(25, a + 11), orbit(38, a + 7)], self.tint, 4)
                self.circle(0, 0, 24, "#6a4025", self.tint, 4)
                self.circle(0, 0, 16, self.tint, self.lit, 5)
                self.circle(-5, -5, 8, self.lit)
            case 25:  # Hexagonal bank of seven optical apertures.
                self.regular(6, 37, 0, self.steel, self.rim, 3)
                self.nodes(6, 22, 6)
                self.circle(0, 0, 9, self.tint, self.lit, 3)
            case 26:  # Oversized magnetic jaws separated by a bright beam cavity.
                self.jaws(14, 56, 17)
                self.armor([(-31, -19), (-12, -22), (-6, -12), (-6, 12), (-12, 22), (-31, 19)])
                self.gem(-11, 0, 10, 6)
                self.line([(0, 0), (52, 0)], self.tint, 5)
                self.line([(27, 0), (50, 0)], self.lit, 2)
            case 27:  # Three offset holographic frames.
                for a in [30, 150, 270]:
                    x, y = orbit(25, a)
                    self.regular(4, 13, a, None, self.tint, 3, x, y)
                    self.regular(4, 8, a, self.steel, self.lit, 2, x, y)
                self.gem(0, 0, 10, 3)
            case 28:  # Dark core, warped accretion arcs and a segmented outer cage.
                for a in [0, 90, 180, 270]:
                    self.arc(39, a + 4, a + 70, self.rim, 6)
                    self.arc(34, a + 10, a + 62, self.tint, 3)
                for r in [18, 24, 29]:
                    self.arc(r, r * 8, r * 8 + 244, self.tint if r == 29 else self.lit, 3)
                self.circle(0, 0, 14, "#090910")
                self.arc(15, -180, 0, self.lit, 4)
            case 29:  # Rainbow toroidal prism with six distinct glass emitters.
                colors = ["#f9a695", "#f9df89", "#aee9b0", "#86dcf5", "#a8a6ff", "#f7a1df"]
                for i, color in enumerate(colors):
                    a = i * 60
                    self.arc(37, a + 2, a + 54, color, 5)
                    x, y = orbit(29, a)
                    self.regular(3, 13, a, color, "#f8edf5", 2, x, y)
                    self.line([(0, 0), (x, y)], color, 3)
                self.gem(0, 0, 16, 6)
            case 30:  # Four gold-armored launch pylons locking into an orbital weapon.
                for a in [0, 90, 180, 270]:
                    self.polygon([orbit(15, a - 27), orbit(35, a - 25),
                                  orbit(52, a - 6), orbit(45, a + 12),
                                  orbit(23, a + 28)], self.steel, self.rim, 3)
                    self.line([orbit(22, a - 6), orbit(41, a - 7), orbit(48, a - 5)], self.tint, 5)
                    self.arc(40, a + 18, a + 69, self.lit, 3)
                self.regular(4, 22, 45, "#3d352d", self.tint, 4)
                self.gem(0, 0, 13, 4)

    def render(self):
        return self.image.resize((CELL, CELL), Image.Resampling.LANCZOS)


def main():
    extra = json.loads((ROOT.parent / "data" / "towers.json").read_text(encoding="utf-8"))
    base = json.loads((ROOT.parent / "data" / "turret.json").read_text(encoding="utf-8"))
    definitions = [base, *extra["towers"]]
    atlas = Image.new("RGBA", (CELL * SIDE, CELL * SIDE))
    for i, (definition, chassis) in enumerate(zip(definitions, BASES, strict=True)):
        color = ImageColor.getrgb(definition["color"])
        base_art, head_art = Sprite(color), Sprite(color)
        base_art.chassis(i + 1, *chassis)
        head_art.head(i + 1)
        for frame, art in enumerate([base_art, head_art], i * 2):
            atlas.paste(art.render(), (frame % SIDE * CELL, frame // SIDE * CELL))
    atlas.save(ROOT / "tower_atlas.png", optimize=True)


if __name__ == "__main__":
    main()
