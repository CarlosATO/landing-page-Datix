/* ──────────────────────────────
   Datix Landing Page - JS
────────────────────────────── */

(function () {
  'use strict';

  /* ── Mobile nav toggle ── */
  const hamburger = document.querySelector('.hamburger');
  const navbar    = document.querySelector('.navbar');

  if (hamburger) {
    hamburger.addEventListener('click', () => {
      hamburger.classList.toggle('open');
      navbar.classList.toggle('nav-mobile-open');
    });

    // Close mobile nav on link click
    document.querySelectorAll('.nav-links a').forEach(link => {
      link.addEventListener('click', () => {
        hamburger.classList.remove('open');
        navbar.classList.remove('nav-mobile-open');
      });
    });
  }

  /* ── Scroll-based navbar shadow ── */
  window.addEventListener('scroll', () => {
    if (window.scrollY > 10) {
      navbar.style.boxShadow = '0 2px 16px rgba(10,37,64,0.10)';
    } else {
      navbar.style.boxShadow = 'none';
    }
  });

  /* ── Smooth scroll for anchor links ── */
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', e => {
      const target = document.querySelector(anchor.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

  /* ── Simple counter animation for hero stats ── */
  function animateCounter(el, target, suffix) {
    const duration = 1800;
    const start    = performance.now();

    function step(now) {
      const elapsed  = now - start;
      const progress = Math.min(elapsed / duration, 1);
      // Ease-out quart
      const eased = 1 - Math.pow(1 - progress, 4);
      el.textContent = Math.round(eased * target).toLocaleString() + suffix;
      if (progress < 1) requestAnimationFrame(step);
    }

    requestAnimationFrame(step);
  }

  const statsObserver = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      const el      = entry.target;
      const raw     = el.dataset.count;
      const suffix  = el.dataset.suffix || '';
      const target  = parseFloat(raw);
      animateCounter(el, target, suffix);
      statsObserver.unobserve(el);
    });
  }, { threshold: 0.5 });

  document.querySelectorAll('[data-count]').forEach(el => statsObserver.observe(el));
}());
