// GROUNDS — comunidad.js
// Tablero de tips (con localStorage) + acordeón de preguntas frecuentes.

document.addEventListener('DOMContentLoaded', function () {

  // ---------- Tablero de tips ----------
  const form = document.getElementById('tip-form');
  const nameInput = document.getElementById('tip-name');
  const textInput = document.getElementById('tip-text');
  const list = document.getElementById('tip-list');
  const emptyState = document.getElementById('tip-empty');
  const STORAGE_KEY = 'groundsTips';

  function cargarTips() {
    const guardado = localStorage.getItem(STORAGE_KEY);
    if (!guardado) return [];
    try {
      return JSON.parse(guardado);
    } catch (e) {
      return [];
    }
  }

  function guardarTips(tips) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(tips));
  }

  function crearTarjetaTip(tip, index) {
    const card = document.createElement('article');
    card.className = 'ticket';
    card.dataset.index = index;

    const code = document.createElement('span');
    code.className = 'ticket-code';
    code.textContent = '#TIP-' + String(index + 1).padStart(3, '0');

    const title = document.createElement('h3');
    title.textContent = tip.nombre;

    const divider = document.createElement('hr');
    divider.className = 'ticket-divider';

    const text = document.createElement('p');
    text.textContent = tip.texto;

    const deleteBtn = document.createElement('button');
    deleteBtn.className = 'tip-delete';
    deleteBtn.type = 'button';
    deleteBtn.textContent = 'Eliminar';
    deleteBtn.dataset.index = index;

    card.appendChild(code);
    card.appendChild(title);
    card.appendChild(divider);
    card.appendChild(text);
    card.appendChild(deleteBtn);

    return card;
  }

  function renderTips() {
    const tips = cargarTips();
    list.innerHTML = '';
    tips.forEach(function (tip, index) {
      list.appendChild(crearTarjetaTip(tip, index));
    });
    emptyState.hidden = tips.length !== 0;
  }

  form.addEventListener('submit', function (event) {
    event.preventDefault();

    const nombre = nameInput.value.trim();
    const texto = textInput.value.trim();
    let valido = true;

    document.getElementById('error-tip-name').textContent = '';
    document.getElementById('error-tip-text').textContent = '';

    if (nombre === '') {
      document.getElementById('error-tip-name').textContent = 'Escribe tu nombre.';
      valido = false;
    }
    if (texto === '') {
      document.getElementById('error-tip-text').textContent = 'Escribe un tip antes de publicar.';
      valido = false;
    }
    if (!valido) return;

    const tips = cargarTips();
    tips.push({ nombre: nombre, texto: texto });
    guardarTips(tips);
    renderTips();
    form.reset();
  });

  // Delegación de eventos para el borrado de tips.
  list.addEventListener('click', function (event) {
    if (!event.target.classList.contains('tip-delete')) return;
    const index = parseInt(event.target.dataset.index, 10);
    const tips = cargarTips();
    tips.splice(index, 1);
    guardarTips(tips);
    renderTips();
  });

  renderTips();

  // ---------- Acordeón FAQ ----------
  const triggers = document.querySelectorAll('.accordion-trigger');
  triggers.forEach(function (trigger) {
    trigger.addEventListener('click', function () {
      const panel = document.getElementById(trigger.getAttribute('aria-controls'));
      const isOpen = trigger.getAttribute('aria-expanded') === 'true';

      trigger.setAttribute('aria-expanded', isOpen ? 'false' : 'true');
      panel.classList.toggle('is-open', !isOpen);
    });
  });
});
