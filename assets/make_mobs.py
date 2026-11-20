"""Paint original neon enemy silhouettes at their native texture sizes."""
from pathlib import Path

from make_towers import Sprite, orbit

DEST = Path(__file__).resolve().parent / "mobs"


def shade(value):
    return (value, value, value)


class Enemy(Sprite):
    def __init__(self, size):
        super().__init__((190, 190, 190), pixels=size)

    def plate(self, points, body=68, edge=146):
        self.polygon(points, shade(body), shade(edge), 2)
        self.line(points[:2], shade(min(235, edge + 38)), 2)

    def trace(self, points, width=2):
        self.line(points, shade(232), width)

    def core(self, x=0, y=0, radius=9, sides=4):
        self.regular(sides, radius + 4, 0, shade(34), shade(137), 2, x, y)
        self.regular(sides, radius, 0, shade(221), shade(255), 2, x, y)
        self.polygon([(x, y - radius * .70), (x + radius * .68, y), (x, y)], shade(255))

    def bolts(self, x, y, n=3):
        for i in range(n):
            self.circle(x + i * 7, y, 1.7, shade(145))

    def vents(self, x, y, n=3, direction=1):
        for i in range(n):
            self.line([(x + i * 6, y), (x + 3 + i * 6, y + direction * 7)], shade(167), 2)

    def bank(self, radius, count, width=3):
        for i in range(count):
            angle = i * 360 / count
            self.arc(radius, angle + 4, angle + 360 / count * .76, shade(210), width)
            self.line([orbit(radius - 4, angle), orbit(radius + 2, angle)], shade(150), 2)


def drone(s):
    s.plate([(37, 0), (13, -14), (-7, -19), (-29, -8), (-22, 0), (-29, 8), (-7, 19), (13, 14)])
    s.trace([(-21, -8), (-5, -11), (12, -9), (29, 0)], 2)
    s.trace([(-21, 8), (-5, 11), (12, 9), (29, 0)], 2)
    s.core(4, 0, 9)
    s.bolts(-16, 0, 2)


def dart(s):
    s.plate([(48, 0), (24, -8), (-33, -25), (-19, -6), (-27, 0), (-19, 6), (-33, 25), (24, 8)], 75)
    for sign in [-1, 1]:
        s.trace([(-25, sign * 18), (-7, sign * 8), (28, sign * 4)], 3)
        s.trace([(-38, sign * 10), (-23, sign * 7)], 2)
    s.core(12, 0, 6)


def hex_shell(s):
    s.plate(orbit_points(6, 39), 59)
    s.plate(orbit_points(6, 30), 88, 125)
    for y in [-18, 17]:
        s.vents(-19, y, 4)
    s.core(8, 0, 11, 6)
    s.trace([(21, -13), (32, 0), (21, 13)], 3)


def swarm(s):
    s.plate([(39, 0), (16, -7), (1, -27), (-18, -29), (-11, -11), (-30, -7), (-30, 7), (-11, 11), (-18, 29), (1, 27), (16, 7)])
    s.core(13, 0, 8, 3)
    for y in [-15, 15]:
        s.circle(-5, y, 5, shade(214), shade(250), 1)


def cell(s):
    for a in [0, 120, 240]:
        x, y = orbit(22, a)
        s.regular(6, 18, a, shade(73), shade(145), 2, x, y)
        s.circle(x, y, 6, shade(200), shade(242), 2)
    s.bank(32, 3)
    s.core(0, 0, 9, 6)


def split(s):
    s.plate([(43, 0), (14, -14), (0, -37), (-14, -14), (-41, 0), (-14, 14), (0, 37), (14, 14)], 81)
    for a in [0, 90, 180, 270]:
        x, y = orbit(22, a)
        s.regular(4, 11, a, shade(175), shade(245), 2, x, y)
    s.core(0, 0, 10)


def conductor(s):
    s.regular(8, 38, 22.5, shade(60), shade(168), 2)
    s.bank(40, 8, 3)
    s.bank(27, 4, 2)
    s.core(radius=13, sides=8)


def guardian(s):
    s.plate([(45, -26), (29, 0), (45, 26), (9, 37), (-41, 27), (-41, -27), (9, -37)], 76)
    s.plate([(-32, -19), (7, -27), (24, -12), (24, 12), (7, 27), (-32, 19)], 98)
    s.trace([(-19, 0), (14, 0)], 7)
    s.trace([(-2, -17), (-2, 17)], 7)
    s.bolts(-27, -20, 3)
    s.bolts(-27, 20, 3)


def relay(s):
    for a in [0, 120, 240]:
        s.plate([orbit(13, a - 25), orbit(43, a - 12), orbit(43, a + 12), orbit(13, a + 25)], 84)
        x, y = orbit(27, a)
        s.core(x, y, 7)
    s.bank(31, 3, 3)
    s.core(radius=8, sides=3)


def tank(s):
    s.plate([(-43, -34), (24, -34), (45, -21), (45, 21), (24, 34), (-43, 34)], 58)
    for sign in [-1, 1]:
        y = sign * 24
        s.plate([(-41, y - 7), (26, y - 7), (38, y), (25, y + 7), (-41, y + 7)], 104)
        for x in range(-32, 28, 11):
            s.line([(x, y - 6), (x + 4, y + 6)], shade(186), 2)
    s.regular(6, 22, 0, shade(72), shade(175), 2)
    s.core(5, 0, 10, 6)


def calamity(s):
    s.plate([(47, 0), (34, -13), (38, -35), (11, -41), (0, -32), (-28, -48), (-49, -26), (-35, 0), (-49, 26), (-28, 48), (0, 32), (11, 41), (38, 35), (34, 13)], 66)
    s.bank(46, 8, 2)
    for a in [45, 135, 225, 315]:
        x, y = orbit(31, a)
        s.trace([(x * .36, y * .36), (x, y)], 3)
        s.core(x, y, 8)
    s.regular(8, 23, 22.5, shade(41), shade(175), 3)
    s.core(radius=14, sides=6)


def boss(s):
    s.plate([(53, 0), (40, -17), (45, -33), (18, -52), (-7, -46), (-29, -52), (-50, -33), (-42, 0),
             (-50, 33), (-29, 52), (-7, 46), (18, 52), (45, 33), (40, 17)], 72, 180)
    for sign in [-1, 1]:
        s.plate([(-43, sign * 31), (-26, sign * 45), (16, sign * 42), (36, sign * 31), (29, sign * 18), (-28, sign * 26)], 108)
        s.trace([(-37, sign * 34), (-24, sign * 39), (12, sign * 37), (27, sign * 29)], 3)
        s.vents(-23, sign * 29, 5, sign)
        s.core(-22, sign * 23, 8, 6)
    s.regular(8, 32, 22.5, shade(45), shade(145), 3)
    s.bank(30, 6, 2)
    s.core(7, 0, 17, 6)
    s.trace([(23, -12), (43, -6), (48, 0), (43, 6), (23, 12)], 3)


def shield(s):
    s.plate(orbit_points(8, 40, 22.5), 68)
    s.regular(8, 31, 22.5, shade(47), shade(168), 3)
    s.bank(42, 4, 4)
    for a in [0, 90, 180, 270]:
        x, y = orbit(29, a)
        s.circle(x, y, 5, shade(220), shade(250), 1)
    s.core(radius=12, sides=8)


def cloak(s):
    s.plate([(47, 0), (10, -19), (-15, -30), (-13, -12), (-42, -26), (-27, -3), (-21, 0), (-27, 3), (-42, 26), (-13, 12), (-15, 30), (10, 19)], 49, 138)
    for sign in [-1, 1]:
        s.trace([(-29, sign * 16), (-9, sign * 11), (16, sign * 10), (34, sign * 3)])
    s.core(4, 0, 8)


def accelerate(s):
    s.plate([(48, 0), (16, -11), (-19, -25), (-32, -17), (-24, 0), (-32, 17), (-19, 25), (16, 11)], 84)
    for y in [-11, 11]:
        s.plate([(-42, y - 5), (-18, y - 5), (7, y), (-18, y + 5), (-42, y + 5)], 120)
        s.trace([(-41, y), (-22, y)], 4)
    s.core(12, 0, 8)
    s.trace([(21, -5), (38, 0), (21, 5)])


def brood(s):
    s.plate(orbit_points(8, 43, 22.5), 61)
    s.bank(40, 6, 3)
    for a in range(0, 360, 60):
        x, y = orbit(24, a)
        s.regular(6, 10, a, shade(155), shade(212), 2, x, y)
        s.circle(x, y, 4, shade(239))
    s.core(radius=10, sides=6)


def energy(s):
    for a in range(0, 360, 120):
        s.plate([orbit(19, a - 22), orbit(42, a - 12), orbit(45, a + 15), orbit(22, a + 28)], 91)
    s.bank(35, 6, 3)
    s.core(radius=15, sides=6)
    s.arc(24, 28, 293, shade(235), 3)


def giant(s):
    s.plate([(-52, -36), (-32, -44), (26, -44), (49, -28), (49, 28), (26, 44), (-32, 44), (-52, 36)], 69, 169)
    for sign in [-1, 1]:
        s.plate([(-49, sign * 28), (-29, sign * 40), (28, sign * 37), (43, sign * 23), (22, sign * 20), (-36, sign * 23)], 112)
        for x in range(-32, 30, 11):
            s.trace([(x, sign * 29), (x + 4, sign * 35)], 2)
        s.bolts(-31, sign * 19, 5)
        s.core(30, sign * 15, 6)
    s.plate([(-30, -13), (17, -17), (37, 0), (17, 17), (-30, 13)], 64)
    s.core(5, 0, 13, 6)
    s.trace([(-31, -9), (-22, 0), (-31, 9)])


def orbit_points(sides, radius, phase=0):
    return [orbit(radius, phase + i * 360 / sides) for i in range(sides)]


def shield_aura(s):
    s.circle(0, 0, 59, None, (191, 191, 191, 124), 2)
    s.circle(0, 0, 55, None, (229, 229, 229, 181), 1)
    for a in range(0, 360, 60):
        s.arc(56, a + 3, a + 34, (255, 255, 255, 224), 4)
        s.line([orbit(52, a + 12), orbit(48, a + 22), orbit(52, a + 31)], (174, 174, 174, 121), 1)


def mantle(s):
    for a in range(0, 360, 60):
        s.arc(58, a + 3, a + 23, (255, 255, 255, 215), 2)
        s.arc(51, a + 30, a + 52, (191, 191, 191, 127), 1)
        s.line([orbit(57, a + 25), orbit(50, a + 28)], (211, 211, 211, 157), 1)


def main():
    variants = [
        ("drone", drone, 192), ("dart", dart, 192), ("hex", hex_shell, 192),
        ("swarm", swarm, 160), ("cell", cell, 192), ("split", split, 192),
        ("ring", conductor, 192), ("guardian", guardian, 256), ("relay", relay, 192),
        ("tank", tank, 256), ("calamity", calamity, 384), ("boss", boss, 512),
        ("shield", shield, 192), ("cloak", cloak, 192), ("accelerate", accelerate, 192),
        ("brood", brood, 192), ("energy", energy, 256), ("giant", giant, 384),
        ("shield_aura", shield_aura, 384), ("mantle", mantle, 384),
    ]
    DEST.mkdir(exist_ok=True)
    for name, paint, size in variants:
        art = Enemy(size)
        paint(art)
        art.render().save(DEST / f"{name}.png", optimize=True)


if __name__ == "__main__":
    main()
