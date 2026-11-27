"""Media: how strokes become a picture (ARCHITECTURE.md 4). A new medium is a new class beside oil."""
from typing import Protocol

import numpy as np


class Medium(Protocol):
    def composite(self, strokes, ref, look, size) -> np.ndarray:
        """Strokes (paint.Strokes, in their fixed order) on a picture of size (W, H), tested against ref -> uint8 RGB."""
