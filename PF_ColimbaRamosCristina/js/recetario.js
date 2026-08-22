// GROUNDS — recetario.js
// Parte 1: calculadora de bebidas a partir de un objeto de recetas.
// Parte 2: hoja de cata interactiva con sliders y localStorage.

document.addEventListener('DOMContentLoaded', function () {

  // ---------- Parte 1: calculadora de bebidas ----------
  const recetas = {
    alto: { onzasBase: 8, shotsRecomendados: 1 },
    grande: { onzasBase: 12, shotsRecomendados: 2 },
    venti: { onzasBase: 16, shotsRecomendados: 2 }
  };

  const nombresLeche = {
    entera: 'leche entera',
    descremada: 'leche descremada',
    avena: 'leche de avena',
    almendra: 'leche de almendra',
    deslactosada: 'leche deslactosada'
  };

  function calcularBebida(tamano, leche, shots) {
    const base = recetas[tamano];
    const onzasLeche = Math.max(base.onzasBase - shots, 4);
    const pasos = [
      'Prepara ' + shots + ' shot(s) de espresso directo sobre la taza.',
      'Vaporiza ' + onzasLeche + ' oz de ' + nombresLeche[leche] + ' hasta unos 60-65°C.',
      'Vierte la leche sobre el espresso dejando una capa fina de espuma.',
      leche === 'avena' || leche === 'almendra'
        ? 'Vierte con cuidado: las leches vegetales generan menos microespuma, vierte más despacio.'
        : 'Ajusta la textura final según el pedido del cliente (más o menos espuma).'
    ];

    return {
      onzasLeche: onzasLeche,
      shotsRecomendados: base.shotsRecomendados,
      shotsElegidos: shots,
      pasos: pasos
    };
  }

  const sizeSelect = document.getElementById('drink-size');
  const milkSelect = document.getElementById('drink-milk');
  const shotsSelect = document.getElementById('drink-shots');
  const resultBox = document.getElementById('drink-result');

  function renderResultado() {
    const tamano = sizeSelect.value;
    const leche = milkSelect.value;
    const shots = parseInt(shotsSelect.value, 10);
    const resultado = calcularBebida(tamano, leche, shots);

    let pasosHtml = '<ol>';
    resultado.pasos.forEach(function (paso) {
      pasosHtml += '<li>' + paso + '</li>';
    });
    pasosHtml += '</ol>';

    resultBox.innerHTML =
      '<p><strong>Leche necesaria:</strong> ' + resultado.onzasLeche + ' oz de ' + nombresLeche[leche] + '</p>' +
      '<p><strong>Shots recomendados para este tamaño:</strong> ' + resultado.shotsRecomendados +
      ' (elegiste ' + resultado.shotsElegidos + ')</p>' +
      pasosHtml;

    localStorage.setItem('groundsRecetario', JSON.stringify({ tamano: tamano, leche: leche, shots: shots }));
  }

  [sizeSelect, milkSelect, shotsSelect].forEach(function (el) {
    el.addEventListener('change', renderResultado);
  });

  (function restaurarBebida() {
    const guardado = localStorage.getItem('groundsRecetario');
    if (!guardado) return;
    try {
      const datos = JSON.parse(guardado);
      if (datos.tamano) sizeSelect.value = datos.tamano;
      if (datos.leche) milkSelect.value = datos.leche;
      if (datos.shots) shotsSelect.value = datos.shots;
    } catch (e) {
      /* localStorage con formato inesperado: se ignora y se usan los valores por defecto */
    }
  })();

  renderResultado();

  // ---------- Parte 2: hoja de cata interactiva ----------
  const criterios = ['aroma', 'acidez', 'cuerpo', 'dulzor', 'retrogusto'];
  const totalLabel = document.getElementById('cupping-total');

  function calcularTotal() {
    let suma = 0;
    criterios.forEach(function (criterio) {
      const valor = parseInt(document.getElementById('score-' + criterio).value, 10);
      suma += valor;
      document.getElementById('out-' + criterio).textContent = valor;
    });
    totalLabel.textContent = suma + ' / 50';

    const datos = {};
    criterios.forEach(function (criterio) {
      datos[criterio] = document.getElementById('score-' + criterio).value;
    });
    localStorage.setItem('groundsCata', JSON.stringify(datos));
  }

  criterios.forEach(function (criterio) {
    document.getElementById('score-' + criterio).addEventListener('input', calcularTotal);
  });

  (function restaurarCata() {
    const guardado = localStorage.getItem('groundsCata');
    if (!guardado) return;
    try {
      const datos = JSON.parse(guardado);
      criterios.forEach(function (criterio) {
        if (datos[criterio]) document.getElementById('score-' + criterio).value = datos[criterio];
      });
    } catch (e) {
      /* localStorage con formato inesperado: se ignora y se usan los valores por defecto */
    }
  })();

  calcularTotal();
});
