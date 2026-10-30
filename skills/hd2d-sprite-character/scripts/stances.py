"""Battle-idle stances (FFBE style: wide low base, weapon leaving the silhouette toward the enemy); ph in [0, 1)."""
import numpy as np
from core import V
from rig import lag, TAU


def low_guard(ph):
    """Two-handed low guard: feet 13 apart along the facing, crouch, lean, hilt at the waist, blade forward-up at the enemy."""
    br = np.sin(TAU * ph)
    return dict(b=-2.6 + 0.5 * br, chest=0.5 * br, crouch=1.2, lean=2.4,
                hilt=V(-2.4, 26.6 + 0.35 * np.sin(TAU * ph - 0.5), 9.6),
                sword=V(-0.66 + 0.03 * np.sin(TAU * ph - 0.9), 0.62, 0.42),
                cape=V(1.4 + lag(ph, 0.6, 0.3), 0, -2.2 + lag(ph, 0.7, 0.32)), fold=0.5 * br,
                tail=V(0.6 + lag(ph, 0.6, 0.22), lag(ph, 0.5, 0.18), -0.6 + lag(ph, 0.8, 0.26)),
                head=V(0, 0.25 * br, 0.5), feet=[V(-6.6, 0, 4.4), V(6.2, 0, -4.2)], ph=ph)


def high_guard(ph):
    """Sword-and-board: shield arm forward covering the chest, blade cocked high over the near shoulder, deep stance."""
    br = np.sin(TAU * ph)
    return dict(b=-2.8 + 0.5 * br, chest=0.5 * br, crouch=1.4, lean=2.6,
                hilt=V(8.0, 41.0 + 0.4 * np.sin(TAU * ph - 0.5), 1.6),
                sword=V(-0.25 + 0.04 * np.sin(TAU * ph - 0.9), 0.9, 0.3),
                off=V(-5.2, 30.0 + 0.3 * br, 9.4), off_grip='fist', shield_dir=V(-0.35, 0.05, 1.0),
                cape=V(1.2 + lag(ph, 0.5, 0.3), 0, -1.6 + lag(ph, 0.6, 0.32)), fold=0.6 * br,
                tail=V(lag(ph, 0.8, 0.2), lag(ph, 0.6, 0.15), -1.0), mane=V(lag(ph, 0.3, 0.2), lag(ph, 0.3, 0.1), 0),
                head=V(0, 0.25 * br, 0.8), feet=[V(-7.0, 0, 5.0), V(6.6, 0, -4.4)], ph=ph)


def caster(ph):
    """Robed caster: upright, staff planted in the near hand, off hand raised forward under a floating orb."""
    br = np.sin(TAU * ph)
    return dict(b=-0.8 + 0.4 * br, chest=0.5 * br, crouch=0.4, lean=1.2,
                hilt=V(7.4, 27.0 + 0.3 * br, 3.2), sword=V(0.05, 1.0, 0.08),
                off=V(-4.0, 29.0 + 0.6 * np.sin(TAU * ph - 0.6), 9.0), off_grip='open',
                cape=V(lag(ph, 0.8, 0.3), 0, -1.0 + lag(ph, 0.6, 0.3)), fold=0.8 * br,
                tail=V(lag(ph, 0.6, 0.2), 0, lag(ph, 0.6, 0.3)), ph=ph,
                head=V(0, 0.25 * br, 0.6), feet=[V(-3.6, 0, 2.2), V(3.6, 0, -1.6)])


def spellcast(ph):
    """Dynamic caster: wide stance leaning in, staff held out beside the near hip tilted away from the body, off arm thrust at the enemy."""
    br = np.sin(TAU * ph)
    return dict(b=-1.8 + 0.4 * br, chest=0.5 * br, crouch=1.2, lean=3.0,
                hilt=V(11.2, 25.4 + 0.3 * np.sin(TAU * ph - 0.4), 6.4), sword=V(0.2, 1.0, 0.16),
                off=V(-9.4, 33.0 + 0.6 * np.sin(TAU * ph - 0.6), 11.0), off_grip='claw',
                palm={-1: V(-1.0, 0.5, 0.4)}, point={-1: V(-0.4, 1.0, 0.2)},
                cape=V(1.6 + lag(ph, 0.8, 0.3), 0, -2.2 + lag(ph, 0.6, 0.3)), fold=0.8 * br,
                tail=V(0.8 + lag(ph, 0.6, 0.2), 0, -0.6 + lag(ph, 0.6, 0.3)), ph=ph,
                head=V(-0.4, 0.25 * br, 0.9), feet=[V(-6.4, 0, 4.0), V(5.6, 0, -3.6)])


def brawler(ph):
    """Upright beast: heavy rocking breath, paws raised forward with claws out, wide flat feet."""
    br = np.sin(TAU * ph)
    return dict(b=-1.2 + 0.9 * br, chest=0.8 * br, crouch=1.0, lean=2.2,
                hands={-1: V(-15.0, 46.0 + 1.0 * np.sin(TAU * ph - 0.4), 11.0), 1: V(16.6, 49.0 + 1.0 * np.sin(TAU * ph - 0.8), 7.0)},
                palm={-1: V(0.2, 0.2, 1.0), 1: V(0.6, 0.2, 0.8)},
                cape=V(0, 0, 0), fold=br, tail=V(0, 0, 0), ph=ph,
                head=V(0, 0.4 * br, 1.2), feet=[V(-6.0, 0, 2.6), V(6.0, 0, -2.0)])


def skulk(ph):
    """Small hunched raider: knees bent, head thrust forward, spear levelled two-handed at the enemy, tail lashing."""
    br = np.sin(TAU * ph)
    return dict(b=-2.4 + 0.5 * br, chest=0.4 * br, crouch=2.4, lean=6.0,
                hilt=V(3.4, 14.6 + 0.4 * np.sin(TAU * ph - 0.5), 5.4), sword=V(0.72, 0.2, 0.62),
                cape=V(0, 0, 0), fold=1.2 * br, ph=ph,
                tail=V(1.4 * np.sin(TAU * ph - 0.6), 0.6 * np.sin(TAU * ph - 1.2), 0), mane=V(0, 0, 0),
                head=V(0, -0.8 + 0.3 * br, 2.2), feet=[V(-5.0, 0, 3.6), V(4.6, 0, -3.2)])


STANCES = dict(low_guard=low_guard, high_guard=high_guard, caster=caster, spellcast=spellcast, brawler=brawler, skulk=skulk)
