// GROUNDS — trivia.js
// Quiz de opción múltiple + leaderboard semanal en localStorage.

document.addEventListener('DOMContentLoaded', function () {

  const preguntas = [
    {
      pregunta: '¿En qué país se descubrió por primera vez el café, según la leyenda de Kaldi?',
      opciones: ['Etiopía', 'Brasil', 'Vietnam', 'Colombia'],
      respuestaCorrecta: 0
    },
    {
      pregunta: '¿Cuál de estos NO es un método de extracción de café?',
      opciones: ['V60', 'Prensa francesa', 'Rosetta', 'Chemex'],
      respuestaCorrecta: 2
    },
    {
      pregunta: '¿Qué grano de café es más ácido y aromático en general?',
      opciones: ['Robusta', 'Arábica', 'Liberica', 'Excelsa'],
      respuestaCorrecta: 1
    },
    {
      pregunta: '¿Cómo se llama la capa de espuma que rompe un partner al iniciar una cata?',
      opciones: ['Crema', 'Costra', 'Nata', 'Reducción'],
      respuestaCorrecta: 1
    },
    {
      pregunta: '¿A qué temperatura aproximada se recomienda vaporizar la leche?',
      opciones: ['30-35°C', '45-50°C', '60-65°C', '85-90°C'],
      respuestaCorrecta: 2
    },
    {
      pregunta: '¿Qué figura de arte latte se hace con vertido recto sin balanceo lateral?',
      opciones: ['Rosetta', 'Tulipán', 'Corazón', 'Cisne'],
      respuestaCorrecta: 2
    },
    {
      pregunta: '¿Qué tueste suele tener más acidez y notas más claras?',
      opciones: ['Tueste oscuro', 'Tueste claro', 'Tueste italiano', 'Tueste francés'],
      respuestaCorrecta: 1
    },
    {
      pregunta: '¿Qué bebida clásica lleva espresso, leche vaporizada y una capa fina de espuma?',
      opciones: ['Americano', 'Latte', 'Cold brew', 'Ristretto'],
      respuestaCorrecta: 1
    },
    {
      pregunta: '¿Qué certificación interna de GROUNDS se enfoca en catas avanzadas?',
      opciones: ['Fundamentos I', 'Liderazgo de turno', 'Coffee Master', 'Atención al cliente'],
      respuestaCorrecta: 2
    },
    {
      pregunta: '¿Qué proceso ocurre antes de tostar el grano de café?',
      opciones: ['Empaquetado', 'Molienda', 'Secado y despulpado', 'Vaporizado'],
      respuestaCorrecta: 2
    }
  ];

  let indiceActual = 0;
  let puntaje = 0;

  const progressLabel = document.getElementById('quiz-progress');
  const codeLabel = document.getElementById('quiz-code');
  const questionLabel = document.getElementById('quiz-question');
  const optionsList = document.getElementById('quiz-options');
  const activeView = document.getElementById('quiz-active');
  const resultView = document.getElementById('quiz-result');
  const finalScoreLabel = document.getElementById('quiz-final-score');

  function renderPregunta() {
    const actual = preguntas[indiceActual];

    progressLabel.textContent = 'Pregunta ' + (indiceActual + 1) + ' de ' + preguntas.length;
    codeLabel.textContent = '#TRIVIA-' + String(indiceActual + 1).padStart(2, '0');
    questionLabel.textContent = actual.pregunta;
    optionsList.innerHTML = '';

    actual.opciones.forEach(function (opcion, index) {
      const li = document.createElement('li');
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'quiz-option';
      btn.textContent = opcion;
      btn.addEventListener('click', function () {
        validarRespuesta(index, btn);
      });
      li.appendChild(btn);
      optionsList.appendChild(li);
    });
  }

  function validarRespuesta(indiceElegido, botonElegido) {
    const actual = preguntas[indiceActual];
    const botones = optionsList.querySelectorAll('.quiz-option');

    botones.forEach(function (btn) { btn.disabled = true; });

    if (indiceElegido === actual.respuestaCorrecta) {
      botonElegido.classList.add('correct');
      puntaje++;
    } else {
      botonElegido.classList.add('incorrect');
      botones[actual.respuestaCorrecta].classList.add('correct');
    }

    setTimeout(function () {
      indiceActual++;
      if (indiceActual < preguntas.length) {
        renderPregunta();
      } else {
        mostrarResultado();
      }
    }, 900);
  }

  function mostrarResultado() {
    activeView.hidden = true;
    resultView.hidden = false;
    finalScoreLabel.textContent = puntaje + ' / ' + preguntas.length;
  }

  renderPregunta();

  // ---------- Leaderboard ----------
  const LEADERBOARD_KEY = 'groundsLeaderboard';
  const TOP_KEY = 'groundsTriviaTop';
  const scoreForm = document.getElementById('score-form');
  const nameInput = document.getElementById('score-name');
  const leaderboardBody = document.getElementById('leaderboard-body');
  const leaderboardEmpty = document.getElementById('leaderboard-empty');
  const restartBtn = document.getElementById('quiz-restart');
  const resetBtn = document.getElementById('reset-leaderboard');

  function cargarLeaderboard() {
    const guardado = localStorage.getItem(LEADERBOARD_KEY);
    if (!guardado) return [];
    try {
      return JSON.parse(guardado);
    } catch (e) {
      return [];
    }
  }

  function renderLeaderboard() {
    const tabla = cargarLeaderboard().sort(function (a, b) { return b.puntaje - a.puntaje; });
    const top5 = tabla.slice(0, 5);

    leaderboardBody.innerHTML = '';
    top5.forEach(function (entrada, index) {
      const tr = document.createElement('tr');
      tr.innerHTML =
        '<td>' + (index + 1) + '</td>' +
        '<td>' + entrada.nombre + '</td>' +
        '<td>' + entrada.puntaje + '</td>' +
        '<td>' + entrada.fecha + '</td>';
      leaderboardBody.appendChild(tr);
    });

    leaderboardEmpty.hidden = top5.length !== 0;

    if (top5.length > 0) {
      localStorage.setItem(TOP_KEY, JSON.stringify({ nombre: top5[0].nombre, puntaje: top5[0].puntaje }));
    } else {
      localStorage.removeItem(TOP_KEY);
    }
  }

  scoreForm.addEventListener('submit', function (event) {
    event.preventDefault();

    const nombre = nameInput.value.trim();
    const errorLabel = document.getElementById('error-score-name');
    errorLabel.textContent = '';

    if (nombre === '') {
      errorLabel.textContent = 'Ingresa tu nombre para registrar el puntaje.';
      return;
    }

    const tabla = cargarLeaderboard();
    tabla.push({
      nombre: nombre,
      puntaje: puntaje,
      fecha: new Date().toLocaleDateString('es-ES')
    });
    localStorage.setItem(LEADERBOARD_KEY, JSON.stringify(tabla));
    renderLeaderboard();
    scoreForm.reset();
  });

  restartBtn.addEventListener('click', function () {
    indiceActual = 0;
    puntaje = 0;
    resultView.hidden = true;
    activeView.hidden = false;
    renderPregunta();
  });

  resetBtn.addEventListener('click', function () {
    const confirmado = confirm('¿Seguro que quieres reiniciar el reto semanal? Esto borrará el leaderboard actual.');
    if (!confirmado) return;
    localStorage.removeItem(LEADERBOARD_KEY);
    localStorage.removeItem(TOP_KEY);
    renderLeaderboard();
  });

  renderLeaderboard();
});
