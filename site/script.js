document.documentElement.classList.add("js");

// Replace this empty value with the final Mac App Store product URL at launch.
const APP_STORE_URL = "";

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const header = document.querySelector("[data-header]");
const navToggle = document.querySelector("[data-nav-toggle]");
const navLinks = document.querySelector("[data-nav-links]");
const toast = document.querySelector("[data-toast]");

document.querySelectorAll("[data-year]").forEach((element) => {
  element.textContent = new Date().getFullYear();
});

const setHeaderState = () => header?.classList.toggle("scrolled", window.scrollY > 12);
setHeaderState();
window.addEventListener("scroll", setHeaderState, { passive: true });

navToggle?.addEventListener("click", () => {
  const isOpen = navToggle.getAttribute("aria-expanded") === "true";
  navToggle.setAttribute("aria-expanded", String(!isOpen));
  navLinks?.classList.toggle("open", !isOpen);
});

navLinks?.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => {
  navToggle?.setAttribute("aria-expanded", "false");
  navLinks.classList.remove("open");
}));

const showToast = (message) => {
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add("visible");
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toast.classList.remove("visible"), 3200);
};

document.querySelectorAll("[data-app-store]").forEach((link) => {
  if (APP_STORE_URL) {
    link.href = APP_STORE_URL;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    document.querySelectorAll("[data-store-status]").forEach((status) => status.hidden = true);
    return;
  }

  link.addEventListener("click", (event) => {
    event.preventDefault();
    document.querySelector("#download")?.scrollIntoView({ behavior: reducedMotion ? "auto" : "smooth" });
    showToast("MotionDock is coming soon to the Mac App Store.");
  });
});

const heroVideo = document.querySelector("[data-hero-video]");
if (reducedMotion) {
  heroVideo?.pause();
  heroVideo?.removeAttribute("autoplay");
} else if (heroVideo) {
  const startHeroVideo = () => heroVideo.play().catch(() => {});
  heroVideo.readyState >= 2
    ? startHeroVideo()
    : heroVideo.addEventListener("canplay", startHeroVideo, { once: true });
}

const reveals = document.querySelectorAll(".reveal");
if (reducedMotion || !("IntersectionObserver" in window)) {
  reveals.forEach((element) => element.classList.add("visible"));
} else {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      const delay = Number(entry.target.dataset.revealDelay || 0) * 90;
      window.setTimeout(() => entry.target.classList.add("visible"), delay);
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.12 });
  reveals.forEach((element) => observer.observe(element));
}

document.querySelectorAll(".faq-list details").forEach((detail) => {
  detail.addEventListener("toggle", () => {
    if (!detail.open) return;
    document.querySelectorAll(".faq-list details[open]").forEach((other) => {
      if (other !== detail) other.open = false;
    });
  });
});
