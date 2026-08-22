// GROUNDS — cursos.js
// Buscador en vivo que filtra la tabla y las tarjetas de cursos a la vez.

document.addEventListener('DOMContentLoaded', function () {
  const searchInput = document.getElementById('course-search');
  const rows = document.querySelectorAll('.course-row');
  const cards = document.querySelectorAll('.course-card');
  const countLabel = document.getElementById('course-count');
  const emptyState = document.getElementById('course-empty');
  const totalCourses = rows.length;

  function matches(el, query) {
    return el.dataset.name.includes(query) || el.dataset.category.includes(query);
  }

  function applySearch() {
    const query = searchInput.value.trim().toLowerCase();
    let visibleCount = 0;

    rows.forEach(function (row) {
      const isVisible = query === '' || matches(row, query);
      row.hidden = !isVisible;
    });

    cards.forEach(function (card) {
      const isVisible = query === '' || matches(card, query);
      card.style.display = isVisible ? '' : 'none';
      if (isVisible) visibleCount++;
    });

    countLabel.textContent = 'Mostrando ' + visibleCount + ' de ' + totalCourses + ' cursos';
    emptyState.hidden = visibleCount !== 0;
  }

  searchInput.addEventListener('input', applySearch);
  applySearch();
});
