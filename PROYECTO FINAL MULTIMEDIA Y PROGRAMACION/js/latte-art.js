// GROUNDS — latte-art.js
// Tabs de figuras + navegación de pasos con barra de progreso,
// y flipbook de la secuencia de vertido (alternativa a video).

document.addEventListener('DOMContentLoaded', function () {

  const figures = {
    corazon: {
      nombre: 'Corazón',
      imagen: 'assets/img/latte-corazon.svg',
      alt: 'Diagrama de arte latte en forma de corazón visto desde arriba',
      pasos: [
        'Calienta la leche a 60-65°C con microespuma fina y brillante.',
        'Inclina la taza y vierte desde una altura media, en el centro del espresso.',
        'Acerca la jarra a la superficie cuando la taza esté a la mitad.',
        'Mueve la jarra levemente hacia atrás para formar el círculo blanco.',
        'Termina con un corte al frente, atravesando el círculo para cerrar el corazón.'
      ]
    },
    rosetta: {
      nombre: 'Rosetta',
      imagen: 'assets/img/latte-rosetta.svg',
      alt: 'Diagrama de arte latte en forma de rosetta visto desde arriba',
      pasos: [
        'Calienta la leche igual que para el corazón: microespuma fina.',
        'Vierte en el centro para crear una base blanca uniforme.',
        'Acerca la jarra a la superficie y comienza a mover de lado a lado.',
        'Reduce el balanceo mientras retrocedes lentamente hacia el borde.',
        'Termina el vertido con una línea recta que atraviesa las hojas formadas.'
      ]
    },
    tulipan: {
      nombre: 'Tulipán',
      imagen: 'assets/img/latte-tulipan.svg',
      alt: 'Diagrama de arte latte en forma de tulipán visto desde arriba',
      pasos: [
        'Vierte un primer círculo pequeño en el centro de la taza.',
        'Detén el vertido un instante para separar la siguiente capa.',
        'Vierte un segundo círculo más grande, empujando al primero hacia el borde.',
        'Repite una tercera vez si la taza lo permite, formando capas apiladas.',
        'Termina con un corte al frente que estira la última capa en punta.'
      ]
    }
  };

  let currentFigure = 'corazon';
  let currentStep = 0;

  const tabs = document.querySelectorAll('#figure-tabs .tab-btn');
  const figureImage = document.getElementById('figure-image');
  const figureTitle = document.getElementById('figure-title');
  const figureSteps = document.getElementById('figure-steps');
  const progressFill = document.getElementById('figure-progress');
  const stepCounter = document.getElementById('step-counter');
  const prevBtn = document.getElementById('step-prev');
  const nextBtn = document.getElementById('step-next');

  function renderFigure() {
    const data = figures[currentFigure];

    figureImage.src = data.imagen;
    figureImage.alt = data.alt;
    figureTitle.textContent = data.nombre;

    figureSteps.innerHTML = '';
    data.pasos.forEach(function (paso, index) {
      const li = document.createElement('li');
      li.textContent = paso;
      if (index === currentStep) li.classList.add('step-current');
      figureSteps.appendChild(li);
    });

    const total = data.pasos.length;
    stepCounter.textContent = 'Paso ' + (currentStep + 1) + ' de ' + total;
    progressFill.style.width = (((currentStep + 1) / total) * 100) + '%';
    prevBtn.disabled = currentStep === 0;
    nextBtn.disabled = currentStep === total - 1;
  }

  tabs.forEach(function (tab) {
    tab.addEventListener('click', function () {
      tabs.forEach(function (t) { t.setAttribute('aria-selected', 'false'); });
      tab.setAttribute('aria-selected', 'true');
      currentFigure = tab.dataset.figure;
      currentStep = 0;
      renderFigure();
    });
  });

  prevBtn.addEventListener('click', function () {
    if (currentStep > 0) {
      currentStep--;
      renderFigure();
    }
  });

  nextBtn.addEventListener('click', function () {
    const total = figures[currentFigure].pasos.length;
    if (currentStep < total - 1) {
      currentStep++;
      renderFigure();
    }
  });

  renderFigure();

  // ---------- Flipbook (alternativa a video) ----------
  const frames = [
    { src: 'assets/img/pour-frame-1.svg', alt: 'Paso 1: taza vacía lista para el vertido, solo espresso en el fondo' },
    { src: 'assets/img/pour-frame-2.svg', alt: 'Paso 2: primer chorro de leche vertido desde el centro' },
    { src: 'assets/img/pour-frame-3.svg', alt: 'Paso 3: la crema se acerca a la superficie, taza casi llena' },
    { src: 'assets/img/pour-frame-4.svg', alt: 'Paso 4: se traza el patrón moviendo la jarra de lado a lado' },
    { src: 'assets/img/pour-frame-5.svg', alt: 'Paso 5: rosetta terminada tras el corte final' }
  ];
  let currentFrame = 0;
  let autoplayTimer = null;

  const flipImg = document.getElementById('flip-frame');
  const flipCounter = document.getElementById('flip-counter');
  const flipPrev = document.getElementById('flip-prev');
  const flipNext = document.getElementById('flip-next');
  const flipPlay = document.getElementById('flip-play');

  function renderFrame() {
    flipImg.src = frames[currentFrame].src;
    flipImg.alt = frames[currentFrame].alt;
    flipCounter.textContent = 'Fotograma ' + (currentFrame + 1) + ' de ' + frames.length;
  }

  function stopAutoplay() {
    if (autoplayTimer) {
      clearInterval(autoplayTimer);
      autoplayTimer = null;
      flipPlay.textContent = 'Reproducir secuencia';
    }
  }

  flipPrev.addEventListener('click', function () {
    stopAutoplay();
    currentFrame = (currentFrame - 1 + frames.length) % frames.length;
    renderFrame();
  });

  flipNext.addEventListener('click', function () {
    stopAutoplay();
    currentFrame = (currentFrame + 1) % frames.length;
    renderFrame();
  });

  flipPlay.addEventListener('click', function () {
    if (autoplayTimer) {
      stopAutoplay();
      return;
    }
    flipPlay.textContent = 'Detener secuencia';
    autoplayTimer = setInterval(function () {
      currentFrame = (currentFrame + 1) % frames.length;
      renderFrame();
    }, 900);
  });

  renderFrame();
});
