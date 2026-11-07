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

  // Wallify's layout table (src/ui/layout.swift): every size's canvas and element positions, in points.
  const layouts = {
    "1x1": { w: 180, h: 180, art: [8, 8, 164, 26], bar: [16, 112, 132], text: [16, 132], title: 116, artist: 137, time: 99, buttons: [90, 48], compact: true },
    "2x1": { w: 360, h: 180, art: [24, 24, 132, 14], bar: [172, 84, 164], text: [172, 164], title: 30, artist: 54, time: 99, buttons: [254, 132] },
    "3x1": { w: 540, h: 180, art: [24, 24, 132, 14], bar: [172, 84, 344], text: [172, 344], title: 30, artist: 54, time: 99, buttons: [344, 132] },
    "1x2": { w: 180, h: 360, art: [16, 20, 148, 18], bar: [16, 252, 148], text: [16, 148], title: 188, artist: 214, time: 264, buttons: [90, 312] },
    "2x2": { w: 360, h: 360, art: [84, 24, 192, 26], bar: [24, 280, 312], text: [24, 312], title: 228, artist: 254, time: 292, buttons: [180, 326] }
  };

  const widget = document.querySelector(".widget");
  if (widget) {
    const $ = (selector) => widget.querySelector(selector);
    const frame = document.querySelector(".frame"), desk = document.querySelector(".desk");
    const title = $("[data-title]"), artist = $("[data-artist]"), next = $("[data-next]"), progress = $("[data-progress]");
    const lineIn = $("[data-line-in]"), lineOut = $("[data-line-out]"), play = $("[data-play]"), like = $(".like");
    const elapsed = $("[data-elapsed]"), total = $("[data-total]");
    const controls = [$("[data-prev]"), play, $("[data-next-btn]")];
    let index = 0, position = 8, playing = true, last = performance.now(), shownLine = null, size = "3x1", jumped = true;
    const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
    const liked = new Set();

    const place = (element, x, y, width, height, radius) => {
      Object.assign(element.style, { left: `${x}px`, top: `${y}px`, width: `${width}px`, height: `${height}px` });
      if (radius !== undefined) element.style.borderRadius = `${radius}px`;
    };

    // Positions every element the way Wallify draws it; CSS transitions morph between sizes like the app.
    const layout = () => {
      const g = layouts[size], [ax, ay, art, radius] = g.art, [tx, tw] = g.text, compact = !!g.compact;
      widget.dataset.size = size;
      widget.dataset.compact = compact;
      Object.assign(widget.style, { width: `${g.w}px`, height: `${g.h}px` });
      place($(".card"), 8, 8, g.w - 16, g.h - 16, 26);
      place($(".art"), ax, ay, art, art, radius);
      widget.style.setProperty("--paused-scale", (art - 20) / art);  // the paused inset is 10 pt per side
      place($(".scrub"), g.bar[0], g.bar[1] - 14, g.bar[2], 33);
      place($(".glow"), ax - art * 0.2, ay - art * 0.2, art * 1.4, art * 1.4);
      place($(".shade"), 8, 92, g.w - 16, g.h - 100);
      const titleSize = compact ? 15 : 17, artistSize = compact ? 11 : 14;
      title.style.fontSize = `${titleSize}px`;
      artist.style.fontSize = `${artistSize}px`;
      place(title, tx, g.title, tw - (compact ? 0 : 26), titleSize * 1.5);  // the title leaves room for the like button
      place(artist, tx, g.artist, tw, artistSize * 1.5);
      place(like, tx + tw - 22, g.title + 1, 22, 22, 11);
      place($(".bar"), g.bar[0], g.bar[1], g.bar[2], 5, 2.5);
      place(elapsed, tx, g.time, 100, 18);
      place(total, tx, g.time, tw, 18);
      place($(".lyrics"), tx, g.time, tw, 19);
      controls.forEach((button, i) => {
        const box = i === 1 ? 40 : 30;
        place(button, g.buttons[0] + (i - 1) * 46 - box / 2, g.buttons[1] - box / 2, box, box, box / 2);
      });
      fit();
    };

    // Scale Wallify's point-sized canvas to the space on the page.
    const fit = () => {
      const g = layouts[size];
      // The scene's fixed height, minus its menu bar and padding, bounds tall sizes so the page never jumps.
      const room = parseFloat(getComputedStyle(desk).minHeight) - 80;
      const scale = Math.min(1, (desk.clientWidth - 40) / g.w, room / g.h);
      widget.style.transform = `scale(${scale})`;
      Object.assign(frame.style, { width: `${g.w * scale}px`, height: `${g.h * scale}px` });
    };
    new ResizeObserver(fit).observe(desk);

    const clock = (seconds) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;

    const lineAt = (track, time) => {
      const loop = track.lines[track.lines.length - 1][0] + 6;  // the lyric sheet repeats through the demo
      const t = time % loop;
      return [...track.lines].reverse().find(([start]) => start <= t)[1];
    };

    // A line reached by playing rises in; one reached by seeking or skipping just appears, as in the app.
    const showLine = (text, animate) => {
      if (text === shownLine) return;
      shownLine = text;
      lineOut.textContent = animate ? lineIn.textContent : "";
      lineOut.className = lineIn.className.replace(" in", "") + " out";
      lineIn.textContent = text || "♪";
      lineIn.className = "line" + (animate ? " in" : "") + (text ? "" : " note");
      // Restart the CSS animations for this change.
      for (const element of [lineIn, lineOut]) { element.style.animation = "none"; void element.offsetWidth; element.style.animation = ""; }
    };

    const syncLike = () => {
      like.setAttribute("aria-pressed", liked.has(index));
      like.setAttribute("aria-label", liked.has(index) ? "Remove from Liked Songs" : "Save to Liked Songs");
    };

    // Stacks a new cover over the old one; the CSS wipe matches Wallify's default Cinematic transition.
    const art = $(".art"), upNext = $(".upnext");
    const setCover = (colors, animate) => {
      const cover = document.createElement("div");
      cover.className = "cover" + (animate ? " enter" : "");
      ["--a", "--b", "--c"].forEach((name, n) => cover.style.setProperty(name, colors[n]));
      const old = [...art.querySelectorAll(".cover")];
      art.insertBefore(cover, upNext);
      if (!animate) { old.forEach((element) => element.remove()); return; }
      old.forEach((element) => element.classList.add("leave"));
      setTimeout(() => old.forEach((element) => element.remove()), 550);
    };

    const load = (i, animate = true) => {
      index = (i + tracks.length) % tracks.length;
      const track = tracks[index], upcoming = tracks[(index + 1) % tracks.length];
      setCover(track.colors, animate);
      [["--art-a", 0], ["--art-b", 1], ["--art-c", 2], ["--tint", 3]].forEach(([name, n]) => widget.style.setProperty(name, track.colors[n]));
      title.textContent = track.title;
      artist.textContent = track.artist;
      total.textContent = clock(track.length);
      next.textContent = `${upcoming.title} — ${upcoming.artist}`;
      syncLike();
      position = 0;
      jumped = true;
    };

    const tick = (now) => {
      if (playing) position += (now - last) / 1000;
      last = now;
      const track = tracks[index];
      if (position >= track.length) load(index + 1);
      progress.style.width = `${(position / track.length) * 100}%`;
      elapsed.textContent = clock(position);
      showLine(lineAt(track, position), !jumped);
      jumped = false;
      requestAnimationFrame(tick);
    };

    $("[data-prev]").addEventListener("click", () => load(position > 3 ? index : index - 1));
    $("[data-next-btn]").addEventListener("click", () => load(index + 1));
    // Wallify's press: the icon shrinks to half in 0.09 s, swaps, then springs back over 0.24 s.
    play.addEventListener("click", () => {
      playing = !playing;
      widget.dataset.playing = playing;
      play.setAttribute("aria-label", playing ? "Pause" : "Play");
      const icon = playing ? "pause" : "play";
      if (reduceMotion.matches) { widget.dataset.icon = icon; return; }
      play.querySelectorAll("svg").forEach((svg) => svg.animate([
        { transform: "scale(1)", easing: "cubic-bezier(.55, .085, .68, .53)" },
        { transform: "scale(.5)", offset: 0.27, easing: "cubic-bezier(.215, .61, .355, 1)" },
        { transform: "scale(1)" }
      ], { duration: 330 }));
      setTimeout(() => { widget.dataset.icon = icon; }, 90);
    });

    // Drag along the bar to seek; the bar grows while held, as when scrubbing in Wallify.
    const scrub = $(".scrub");
    const seekTo = (event) => {
      const box = $(".bar").getBoundingClientRect();
      position = Math.min(1, Math.max(0, (event.clientX - box.left) / box.width)) * tracks[index].length;
      jumped = true;
    };
    scrub.addEventListener("pointerdown", (event) => {
      scrub.setPointerCapture(event.pointerId);
      widget.dataset.seeking = "true";
      seekTo(event);
    });
    scrub.addEventListener("pointermove", (event) => { if (widget.dataset.seeking === "true") seekTo(event); });
    const release = (event) => {
      if (widget.dataset.seeking !== "true") return;
      if (event.type === "pointerup") seekTo(event);
      widget.dataset.seeking = "false";
    };
    scrub.addEventListener("pointerup", release);
    scrub.addEventListener("pointercancel", release);
    like.addEventListener("click", () => {
      liked.has(index) ? liked.delete(index) : liked.add(index);
      syncLike();
    });

    const lyricsToggle = document.querySelector("[data-lyrics-toggle]");
    lyricsToggle.addEventListener("click", () => {
      const on = widget.dataset.lyrics !== "true";
      widget.dataset.lyrics = on;
      lyricsToggle.setAttribute("aria-pressed", on);
    });

    const sizeButtons = document.querySelectorAll("[data-size-btn]");
    const choose = (button) => {
      sizeButtons.forEach((other) => other.setAttribute("aria-checked", other === button));
      size = button.dataset.sizeBtn;
      layout();
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

    // The first layout appears in place; later size changes animate.
    widget.classList.add("instant");
    load(0, false);
    position = 8;
    layout();
    requestAnimationFrame(() => requestAnimationFrame(() => widget.classList.remove("instant")));
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
