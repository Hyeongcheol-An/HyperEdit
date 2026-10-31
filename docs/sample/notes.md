# Notes · 메모

## 2026-08-12 (수) 09:10
Kickoff for the editor rewrite. Decided on TextKit 2 and one plain-text notes file.
에디터 재작성 시작. TextKit 2 와 단일 메모 파일로 결정.

- [ ] Sketch the ribbon layout
- [x] Measure typing latency on a 1.3 MB file → 3.1 ms per keystroke

## 2026-09-03 (목) 14:45
[Reading] Designing Data-Intensive Applications, chapter 3 — LSM trees vs B-trees
가. 쓰기 증폭(write amplification) 정리
나. 컴팩션 전략 비교: size-tiered vs leveled
1) 메모 파일에도 append-only 가 잘 맞는다
2) 검색은 인덱스를 따로 둔다 (FTS5)

## 2026-10-02 (금) 08:20
Quick calculation while planning the release:  3 + 0.5 + 0.25 ⇒ 3.75 days

```python
def estimate(days, buffer=0.25):
    """Add a review buffer to a raw estimate."""
    return days * (1 + buffer)
```

Links to keep
- https://developer.apple.com/documentation/appkit/nstextview
- https://zed.dev/docs/themes

## 2026-10-30 (금) 16:05
Column mode test block (⌥C, then ⇧↓):
item_a	120	done
item_b	95	in progress
item_c	210	blocked

TODO
- 다크/라이트 기본 테마 정리
- README 영문판 작성
- Homebrew cask 등록
