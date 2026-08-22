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
});
