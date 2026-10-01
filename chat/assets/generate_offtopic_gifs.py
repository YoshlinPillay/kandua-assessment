"""Generate the off-topic meme GIFs shown when a question isn't about Juan (chat/agent.py `off_topic` tool).

Self-made on purpose: no hot-linked third-party GIFs (copyright, availability, tracking). Re-run with
`.venv/bin/python chat/assets/generate_offtopic_gifs.py` to rebuild chat/assets/offtopic_*.gif.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
SIZE = (420, 300)
CAPTIONS = [
    ("404", "Juan not found in your question"),
    ("ONE DOES NOT SIMPLY", "ask me about anything but Juan"),
    ("I ONLY KNOW ONE GUY", "and he's at the bar again"),
]


def font(size: int) -> ImageFont.ImageFont:
    for name in ("DejaVuSans-Bold.ttf", "Arial Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def mug(draw: ImageDraw.ImageDraw, cx: int, cy: int, tilt: float) -> None:
    """A beer mug that wobbles: glass, beer, foam, handle, bubbles."""
    dx = int(10 * math.sin(tilt))
    body = [
        (cx - 45 + dx, cy - 55),
        (cx + 45 + dx, cy - 55),
        (cx + 40 - dx, cy + 60),
        (cx - 40 - dx, cy + 60),
    ]
    draw.polygon(body, fill="#F2A900", outline="#7A4A00", width=4)
    draw.arc([cx + 18 + dx, cy - 35, cx + 72 + dx, cy + 30], start=-75, end=75, fill="#7A4A00", width=9)
    for i, ox in enumerate((-40, -15, 10, 35)):
        r = 20 + 4 * math.sin(tilt * 2 + i)
        draw.ellipse([cx + ox - r + dx, cy - 58 - r / 2, cx + ox + r + dx, cy - 58 + r / 2], fill="white")
    for i in range(5):
        by = cy + 50 - ((tilt * 40 + i * 23) % 100)
        draw.ellipse([cx - 25 + i * 12 + dx, by, cx - 19 + i * 12 + dx, by + 6], fill="#FFE08A")


def render(top: str, bottom: str, path: Path, frames: int = 16) -> None:
    images = []
    for f in range(frames):
        img = Image.new("RGB", SIZE, "#1F2937")
        draw = ImageDraw.Draw(img)
        mug(draw, SIZE[0] // 2, SIZE[1] // 2 + 10, tilt=2 * math.pi * f / frames)
        for text, y, size in ((top, 8, 34), (bottom, SIZE[1] - 40, 22)):
            fnt = font(size)
            while draw.textlength(text, font=fnt) > SIZE[0] - 24 and size > 12:  # shrink to fit the frame
                size -= 2
                fnt = font(size)
            width = draw.textlength(text, font=fnt)
            draw.text(
                ((SIZE[0] - width) / 2, y), text, font=fnt, fill="white", stroke_width=3, stroke_fill="black"
            )
        images.append(img.convert("P", palette=Image.Palette.ADAPTIVE, colors=64))
    images[0].save(path, save_all=True, append_images=images[1:], duration=80, loop=0, optimize=True)


if __name__ == "__main__":
    for i, (top, bottom) in enumerate(CAPTIONS, start=1):
        render(top, bottom, HERE / f"offtopic_{i}.gif")
        print(f"wrote chat/assets/offtopic_{i}.gif")
