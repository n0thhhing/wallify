// Interactive widget preview with made-up songs, and a download link that follows the latest release.
(() => {
  const tracks = [
    { title: "Paper Satellites", artist: "Night Arcade", length: 196, colors: ["#ff8a5c", "#7a3cff", "#1c1033", "#ffb59c"],
      lines: [[0, ""], [6, "Static on the radio, stars on the floor"], [12, "We were building rockets out of paper and tape"],
              [18, "Counting down the minutes till the city's awake"], [24, ""], [28, "Fold me into something that can fly"],
              [34, "Paper satellites across the sky"], [40, ""]] },
    { title: "Low Tide Glow", artist: "Marlow & the Lanterns", length: 214, colors: ["#3fd2c7", "#2f6bff", "#0b1a2e", "#9ce8df"],
      lines: [[0, ""], [5, "Shoes in our hands at the edge of the sea"], [11, "The lighthouse blinking slow for you and me"],
              [17, "Every wave keeps the time we forgot"], [23, ""], [27, "Hold the low tide glow"], [33, "Before it lets us go"], [39, ""]] },
    { title: "Window Seat", artist: "Kei Moreno", length: 181, colors: ["#ffd25c", "#ff4f7a", "#2a0f1f", "#ffe29c"],
      lines: [[0, ""], [4, "Fields turning gold at a hundred miles an hour"], [10, "Headphones on, the world's a music video"],
              [16, "I don't need to know where this train will go"], [22, ""], [26, "Window seat, window seat"], [32, "Let the morning play on repeat"], [38, ""]] }
  ];

  const widget = document.querySelector(".widget");
  if (widget) {
    const $ = (selector) => widget.querySelector(selector);
    const title = $("[data-title]"), artist = $("[data-artist]"), next = $("[data-next]"), progress = $("[data-progress]");
    const lineIn = $("[data-line-in]"), lineOut = $("[data-line-out]"), play = $("[data-play]"), like = $(".like");
    let index = 0, position = 8, playing = true, last = performance.now(), shownLine = null;
    const liked = new Set();

    const lineAt = (track, time) => {
      const loop = track.lines[track.lines.length - 1][0] + 6;  // the lyric sheet repeats through the demo
      const t = time % loop;
      return [...track.lines].reverse().find(([start]) => start <= t)[1];
    };

    const showLine = (text) => {
      if (text === shownLine) return;
      shownLine = text;
      lineOut.textContent = lineIn.textContent;
      lineOut.className = lineIn.className.replace(" in", "") + " out";
      lineIn.textContent = text || "♪";
      lineIn.className = "line in" + (text ? "" : " note");
      // Restart the CSS animations for this change.
      for (const element of [lineIn, lineOut]) { element.style.animation = "none"; void element.offsetWidth; element.style.animation = ""; }
    };

    const load = (i) => {
      index = (i + tracks.length) % tracks.length;
      const track = tracks[index], upcoming = tracks[(index + 1) % tracks.length];
      [["--art-a", 0], ["--art-b", 1], ["--art-c", 2], ["--tint", 3]].forEach(([name, n]) => widget.style.setProperty(name, track.colors[n]));
      title.textContent = track.title;
      artist.textContent = track.artist;
      next.textContent = `${upcoming.title} — ${upcoming.artist}`;
      like.setAttribute("aria-pressed", liked.has(index));
      like.setAttribute("aria-label", liked.has(index) ? "Remove from Liked Songs" : "Save to Liked Songs");
      position = 0;
      shownLine = null;
    };

    const tick = (now) => {
      if (playing) position += (now - last) / 1000;
      last = now;
      const track = tracks[index];
      if (position >= track.length) load(index + 1);
      progress.style.width = `${(position / track.length) * 100}%`;
      showLine(lineAt(track, position));
      requestAnimationFrame(tick);
    };

    $("[data-prev]").addEventListener("click", () => load(position > 3 ? index : index - 1));
    $("[data-next-btn]").addEventListener("click", () => load(index + 1));
    play.addEventListener("click", () => {
      playing = !playing;
      widget.dataset.playing = playing;
      play.setAttribute("aria-label", playing ? "Pause" : "Play");
    });
    like.addEventListener("click", () => {
      liked.has(index) ? liked.delete(index) : liked.add(index);
      like.setAttribute("aria-pressed", liked.has(index));
      like.setAttribute("aria-label", liked.has(index) ? "Remove from Liked Songs" : "Save to Liked Songs");
    });

    const sizeButtons = document.querySelectorAll("[data-size-btn]");
    const choose = (button) => {
      sizeButtons.forEach((other) => other.setAttribute("aria-checked", other === button));
      widget.dataset.size = button.dataset.sizeBtn;
    };
    sizeButtons.forEach((button, i) => {
      button.addEventListener("click", () => choose(button));
      // Arrow keys move between sizes, as in a native radio group.
      button.addEventListener("keydown", (event) => {
        const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
        if (!step) return;
        event.preventDefault();
        const target = sizeButtons[(i + step + sizeButtons.length) % sizeButtons.length];
        choose(target);
        target.focus();
      });
    });

    load(0);
    position = 8;
    requestAnimationFrame(tick);
  }

  // Point Download at the latest release's disk image; the releases page stays as the fallback.
  fetch("https://api.github.com/repos/n0thhhing/wallify/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
    .then((response) => (response.ok ? response.json() : null))
    .then((release) => {
      const asset = release?.assets?.find((file) => file.name.endsWith(".dmg"));
      if (!asset || !asset.browser_download_url.startsWith("https://github.com/")) return;
      const version = (release.tag_name || "").replace(/^v/, "");
      document.querySelectorAll("[data-download]").forEach((link) => { link.href = asset.browser_download_url; });
      document.querySelectorAll("[data-download-label]").forEach((label) => { label.textContent = `Download ${version}`; });
    })
    .catch(() => {});
})();
