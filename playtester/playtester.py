"""
Clawdia's AI Playtester 🦞
Launches the game, plays it via Playwright, screenshots each round,
sends screenshots to the vision model for feedback, iterates.
"""

import asyncio
import base64
import json
import os
import subprocess
import sys
import time
import random
from pathlib import Path
from playwright.async_api import async_playwright

GAME_DIR = Path(__file__).parent.parent / "export" / "web"
SCREENSHOTS_DIR = Path(__file__).parent / "screenshots"
SCREENSHOTS_DIR.mkdir(exist_ok=True)
REPORT_PATH = Path(__file__).parent / "feedback_report.md"

PORT = 8765
ROUNDS = 3  # play N rounds and gather feedback
PLAY_DURATION = 18  # seconds per round

async def serve_game():
    """Serve the exported web game on localhost."""
    proc = subprocess.Popen(
        ["python3", "-m", "http.server", str(PORT), "--directory", str(GAME_DIR)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    await asyncio.sleep(1)
    return proc

async def play_round(page, round_num: int) -> list[str]:
    """Play a single round, take screenshots, return screenshot paths."""
    screenshots = []
    print(f"\n🎮 Round {round_num} starting...")

    # Click Play button
    try:
        await page.click("canvas", timeout=3000)
    except:
        pass

    # Inject a JS auto-player that moves the basket toward falling animals
    await page.evaluate("""
    () => {
        window.__clawdiaBot = true;

        // Override: track animals and move basket toward nearest one
        const origRAF = window.requestAnimationFrame;
        let frame = 0;
        window.requestAnimationFrame = function(cb) {
            return origRAF(function(ts) {
                frame++;
                // Every 3 frames, nudge targetX toward nearest animal
                if (frame % 3 === 0 && window.gameInstance) {
                    try {
                        const animals = window.gameInstance.animals || [];
                        const canvas = document.querySelector('canvas');
                        // We can't easily hook Godot internals via JS,
                        // so we simulate human-like mouse movement instead
                    } catch(e) {}
                }
                cb(ts);
            });
        };
    }
    """)

    # Simulate human-like mouse movement to play the game
    canvas = await page.query_selector("canvas")
    box = await canvas.bounding_box()
    cx = box["x"] + box["width"] / 2
    cy = box["y"] + box["height"] / 2
    w = box["width"]

    # Click to start
    await page.mouse.click(cx, cy)
    await asyncio.sleep(0.5)

    start = time.time()
    positions = [0.2, 0.4, 0.5, 0.6, 0.8]  # patrol across basket positions
    pos_idx = 0
    shot_times = [2, 5, 10, 15]

    while time.time() - start < PLAY_DURATION:
        elapsed = time.time() - start

        # Screenshot at key moments
        if shot_times and elapsed >= shot_times[0]:
            shot_path = str(SCREENSHOTS_DIR / f"round{round_num}_t{int(elapsed)}s.png")
            await page.screenshot(path=shot_path)
            screenshots.append(shot_path)
            print(f"  📸 Screenshot at t={int(elapsed)}s")
            shot_times.pop(0)

        # Move basket in a human-like patrol with some randomness
        target_x = box["x"] + w * positions[pos_idx % len(positions)]
        target_x += random.uniform(-20, 20)
        await page.mouse.move(target_x, cy - 50, steps=3)

        # Occasionally change direction
        if random.random() < 0.15:
            pos_idx += random.choice([-1, 1, 1, 2])

        await asyncio.sleep(0.08)

    # Final screenshot
    shot_path = str(SCREENSHOTS_DIR / f"round{round_num}_final.png")
    await page.screenshot(path=shot_path)
    screenshots.append(shot_path)
    print(f"  📸 Final screenshot")

    return screenshots

def analyze_screenshots_with_vision(round_num: int, screenshots: list[str]) -> str:
    """Send screenshots to Claude vision for game feedback."""
    try:
        import anthropic
    except ImportError:
        return f"[anthropic SDK not available — install with: pip install anthropic]\nScreenshots saved: {screenshots}"

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return f"[No ANTHROPIC_API_KEY set — screenshots saved at: {screenshots}]"

    client = anthropic.Anthropic(api_key=api_key)

    content = [
        {
            "type": "text",
            "text": f"""You are Clawdia 🦞, an AI game designer and playtester for the indie studio "Raining Cats & Dogs".
You just played round {round_num} of "It's Raining Cats & Dogs" — a vertical slice of a browser catcher game.

The attached screenshots are from the playthrough (chronological order).

Please give honest, specific feedback as a playtester AND game designer:

1. **Visual clarity** — Can you tell what's happening? Are the UI elements readable?
2. **Feel** — Does the catch mechanic look satisfying? Any visual issues?
3. **Pacing** — Does it look too fast/slow/just right?
4. **Bugs/issues** — Anything broken or weird you can see?
5. **Top 1-2 improvements** — What would make the biggest difference right now?

Be direct. This is a vertical slice — we want honest cuts, not praise.
End with a one-line verdict: SHIP IT / NEEDS WORK / BROKEN."""
        }
    ]

    for path in screenshots:
        with open(path, "rb") as f:
            img_data = base64.standard_b64encode(f.read()).decode("utf-8")
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": img_data
            }
        })

    response = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=1024,
        messages=[{"role": "user", "content": content}]
    )

    return response.content[0].text

async def main():
    print("🦞 Clawdia's AI Playtester starting...")
    print(f"   Game: {GAME_DIR}")
    print(f"   Rounds: {ROUNDS}")
    print(f"   Screenshots: {SCREENSHOTS_DIR}")

    server = await serve_game()
    print(f"   Server: http://localhost:{PORT}")

    all_feedback = []

    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=False,  # visible so you can watch!
                args=["--autoplay-policy=no-user-gesture-required"]
            )
            context = await browser.new_context(
                viewport={"width": 480, "height": 700},
                ignore_https_errors=True
            )
            page = await context.new_page()

            # Silence SharedArrayBuffer warnings (Godot web needs these headers ideally)
            await page.goto(f"http://localhost:{PORT}/index.html", wait_until="networkidle")
            await asyncio.sleep(3)  # let Godot init

            for round_num in range(1, ROUNDS + 1):
                screenshots = await play_round(page, round_num)

                print(f"\n🤖 Sending round {round_num} to vision AI for feedback...")
                feedback = analyze_screenshots_with_vision(round_num, screenshots)
                all_feedback.append(f"## Round {round_num} Feedback\n\n{feedback}")
                print(f"\n{'='*50}")
                print(feedback)
                print('='*50)

                # Brief pause between rounds
                if round_num < ROUNDS:
                    await asyncio.sleep(2)

            await browser.close()

    finally:
        server.terminate()
        print("\n🛑 Server stopped.")

    # Write full report
    report = f"# 🦞 Clawdia's Playtester Report\n\n"
    report += f"Game: It's Raining Cats & Dogs  \nDate: {time.strftime('%Y-%m-%d %H:%M')}  \nRounds played: {ROUNDS}\n\n---\n\n"
    report += "\n\n---\n\n".join(all_feedback)
    report += "\n\n---\n\n## Next Steps\n\nReview feedback above and prioritize the top issues before sharing with James.\n"

    REPORT_PATH.write_text(report)
    print(f"\n✅ Full report saved to: {REPORT_PATH}")

if __name__ == "__main__":
    asyncio.run(main())
