// GROUNDS — nav.js
// Menú móvil (hamburguesa) + año dinámico en el footer.
// Se importa en las 8 páginas del sitio.

document.addEventListener('DOMContentLoaded', function () {
  const toggle = document.querySelector('.nav-toggle');
  const menu = document.getElementById('nav-menu');

  if (toggle && menu) {
    toggle.addEventListener('click', function () {
      const isOpen = menu.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    });

    menu.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        menu.classList.remove('is-open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    });
  }

  const year = new Date().getFullYear();
  document.querySelectorAll('[data-year]').forEach(function (el) {
    el.textContent = year;
  });

  // ---------- Scroll-reveal: las tarjetas y bloques aparecen con una
  // animación al entrar en pantalla, en vez de estar ahí de forma estática.
  // Si el navegador no soporta IntersectionObserver, todo queda visible
  // igual (no depende de JS para poder leerse). ----------
  const revealTargets = document.querySelectorAll(
    '.ticket, .product-card, .card, .accordion-item'
  );

  if (revealTargets.length && 'IntersectionObserver' in window) {
    revealTargets.forEach(function (el, index) {
      el.classList.add('reveal');
      el.style.transitionDelay = (index % 3) * 90 + 'ms';
    });

    const revealObserver = new IntersectionObserver(function (entries, observer) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.01, rootMargin: '0px 0px 150px 0px' });

    revealTargets.forEach(function (el) { revealObserver.observe(el); });

    // Red de seguridad: si por lo que sea (captura de pantalla, lector,
    // navegador raro) el observer nunca dispara para algún elemento,
    // igual se vuelve visible solo a los 2 segundos. Nunca debe quedar
    // contenido oculto de forma permanente.
    setTimeout(function () {
      document.querySelectorAll('.reveal:not(.is-visible)').forEach(function (el) {
        el.classList.add('is-visible');
      });
    }, 2000);
  }
});
