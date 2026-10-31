"""Small helpers kept next to the notes."""
from datetime import datetime


def stamp() -> str:
    """Same format HyperEdit inserts with F7."""
    return datetime.now().strftime("## %Y-%m-%d (%a) %H:%M")


def dedupe(lines: list[str]) -> list[str]:
    seen: set[str] = set()
    out = []
    for line in lines:
        if line not in seen:
            seen.add(line)
            out.append(line)
    return out
