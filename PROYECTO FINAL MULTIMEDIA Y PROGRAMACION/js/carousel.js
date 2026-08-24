// GROUNDS — carousel.js
// Carrusel accesible reutilizable: flechas, puntos, teclado y pausa en
// hover. Si una diapositiva tiene <video>, se reproduce solo la activa
// y se pausan las demás. Se importa únicamente en las páginas que tienen
// un elemento [data-carousel].

document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('[data-carousel]').forEach(function (carousel) {
    const track = carousel.querySelector('.carousel-track');
    const slides = Array.from(track.children);
    const prevBtn = carousel.querySelector('.carousel-prev');
    const nextBtn = carousel.querySelector('.carousel-next');
    const dotsWrap = carousel.querySelector('.carousel-dots');
    let index = 0;
    let autoTimer = null;

    slides.forEach(function (_, i) {
      const dot = document.createElement('button');
      dot.type = 'button';
      dot.className = 'carousel-dot';
      dot.setAttribute('aria-label', 'Ir a la diapositiva ' + (i + 1) + ' de ' + slides.length);
      dot.addEventListener('click', function () { goTo(i); });
      dotsWrap.appendChild(dot);
    });
    const dots = Array.from(dotsWrap.children);

    function update() {
      track.style.transform = 'translateX(-' + (index * 100) + '%)';
      dots.forEach(function (dot, i) {
        dot.setAttribute('aria-current', i === index ? 'true' : 'false');
      });
      slides.forEach(function (slide, i) {
        const video = slide.querySelector('video');
        if (!video) return;
        if (i === index) {
          video.play().catch(function () { /* autoplay bloqueado: no pasa nada, sigue con controles */ });
        } else {
          video.pause();
        }
      });
    }

    function goTo(i) {
      index = (i + slides.length) % slides.length;
      update();
    }

    function startAutoplay() {
      autoTimer = setInterval(function () { goTo(index + 1); }, 6000);
    }
    function stopAutoplay() {
      clearInterval(autoTimer);
    }

    prevBtn.addEventListener('click', function () { stopAutoplay(); goTo(index - 1); startAutoplay(); });
    nextBtn.addEventListener('click', function () { stopAutoplay(); goTo(index + 1); startAutoplay(); });

    carousel.setAttribute('tabindex', '0');
    carousel.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowLeft') { stopAutoplay(); goTo(index - 1); startAutoplay(); }
      if (event.key === 'ArrowRight') { stopAutoplay(); goTo(index + 1); startAutoplay(); }
    });

    carousel.addEventListener('mouseenter', stopAutoplay);
    carousel.addEventListener('mouseleave', startAutoplay);

    const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    update();
    if (!prefersReducedMotion) startAutoplay();
  });
});
