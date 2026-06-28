const revealItems = document.querySelectorAll(".reveal");
const navLinks = document.querySelectorAll(".nav-links a");
const sections = [...navLinks].map((link) => document.querySelector(link.getAttribute("href")));
const captureTarget = new URLSearchParams(window.location.search).get("capture");
const heroWindow = document.querySelector(".hero-window");
window.musicHeroAnimationState = {
  heroLoadedAt: null,
  startedAt: null,
  status: "pending"
};
document.documentElement.dataset.heroAnimationStatus = "pending";

const startHeroAnimation = () => {
  window.requestAnimationFrame(() => {
    document.documentElement.classList.remove("hero-animation-pending");
    document.documentElement.classList.add("hero-assets-ready");
    window.musicHeroAnimationState.startedAt = performance.now();
    window.musicHeroAnimationState.status = "started";
    document.documentElement.dataset.heroAnimationStatus = "started";
    document.documentElement.dataset.heroAnimationStartedAt = String(
      window.musicHeroAnimationState.startedAt
    );
  });
};

const prepareHeroAnimation = async () => {
  if (!heroWindow) {
    startHeroAnimation();
    return;
  }

  try {
    const heroURL = heroWindow.currentSrc || heroWindow.getAttribute("src") || heroWindow.src;
    if (heroWindow.complete && heroWindow.naturalWidth > 0) {
      window.musicHeroAnimationState.heroLoadedAt = performance.now();
      document.documentElement.dataset.heroImageLoadedAt = String(
        window.musicHeroAnimationState.heroLoadedAt
      );
      startHeroAnimation();
      return;
    }

    await new Promise((resolve) => {
      const preloader = new Image();
      let interval = 0;
      const finish = () => {
        if (interval) {
          window.clearInterval(interval);
        }
        resolve();
      };
      preloader.decoding = "async";
      preloader.fetchPriority = "high";
      preloader.addEventListener("load", finish, { once: true });
      preloader.addEventListener("error", finish, { once: true });
      preloader.src = heroURL;
      if (preloader.complete && preloader.naturalWidth > 0) {
        finish();
        return;
      }
      interval = window.setInterval(() => {
        if (
          (heroWindow.complete && heroWindow.naturalWidth > 0)
          || (preloader.complete && preloader.naturalWidth > 0)
        ) {
          finish();
        }
      }, 40);
    });

    if (heroWindow.decode) {
      heroWindow.decode().catch(() => {
        // The hero file has loaded. Decode is best-effort so the gate cannot stall.
      });
    }
  } catch {
    // If the preload fails, start the page instead of leaving visitors stuck.
  }

  window.musicHeroAnimationState.heroLoadedAt = performance.now();
  document.documentElement.dataset.heroImageLoadedAt = String(
    window.musicHeroAnimationState.heroLoadedAt
  );
  startHeroAnimation();
};

prepareHeroAnimation();

const revealObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        revealObserver.unobserve(entry.target);
      }
    }
  },
  { threshold: 0.16, rootMargin: "0px 0px -8% 0px" }
);

revealItems.forEach((item) => revealObserver.observe(item));

const sectionObserver = new IntersectionObserver(
  (entries) => {
    const visible = entries
      .filter((entry) => entry.isIntersecting)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

    if (!visible) return;

    navLinks.forEach((link) => {
      link.classList.toggle("active", link.getAttribute("href") === `#${visible.target.id}`);
    });
  },
  { threshold: [0.28, 0.45, 0.62] }
);

sections.filter(Boolean).forEach((section) => sectionObserver.observe(section));

if (captureTarget) {
  document.documentElement.dataset.capture = captureTarget;
}

document.querySelectorAll("[data-slider]").forEach((slider) => {
  const track = slider.querySelector("[data-slider-track]");
  const slides = [...slider.querySelectorAll(".import-slide")];
  const dots = [...slider.querySelectorAll("[data-slider-dot]")];
  const previousButton = slider.querySelector("[data-slider-prev]");
  const nextButton = slider.querySelector("[data-slider-next]");
  const title = slider.querySelector("[data-slider-title]");
  const step = slider.querySelector("[data-slider-step]");
  let activeIndex = 0;
  let frame = 0;

  if (!track || slides.length === 0) return;

  const clampIndex = (index) => Math.max(0, Math.min(slides.length - 1, index));

  const update = (index) => {
    activeIndex = clampIndex(index);
    const activeSlide = slides[activeIndex];
    title.textContent = activeSlide.dataset.title || "";
    step.textContent = activeSlide.dataset.step || "";
    dots.forEach((dot, dotIndex) => dot.classList.toggle("active", dotIndex === activeIndex));
    previousButton.disabled = activeIndex === 0;
    nextButton.disabled = activeIndex === slides.length - 1;
  };

  const goTo = (index) => {
    const nextIndex = clampIndex(index);
    track.scrollTo({
      left: slides[nextIndex].offsetLeft - track.offsetLeft,
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
    });
    update(nextIndex);
  };

  previousButton.addEventListener("click", () => goTo(activeIndex - 1));
  nextButton.addEventListener("click", () => goTo(activeIndex + 1));

  dots.forEach((dot, dotIndex) => {
    dot.addEventListener("click", () => goTo(dotIndex));
  });

  track.addEventListener("keydown", (event) => {
    if (event.key === "ArrowLeft") {
      event.preventDefault();
      goTo(activeIndex - 1);
    }
    if (event.key === "ArrowRight") {
      event.preventDefault();
      goTo(activeIndex + 1);
    }
  });

  track.addEventListener(
    "scroll",
    () => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        const slideWidth = slides[1]
          ? slides[1].offsetLeft - slides[0].offsetLeft
          : slides[0].getBoundingClientRect().width;
        update(Math.round(track.scrollLeft / Math.max(slideWidth, 1)));
        frame = 0;
      });
    },
    { passive: true }
  );

  update(0);
});
