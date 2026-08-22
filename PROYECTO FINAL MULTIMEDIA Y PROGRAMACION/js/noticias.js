// GROUNDS — noticias.js
// Filtro por categoría + buscador de texto sobre los artículos de noticias.

document.addEventListener('DOMContentLoaded', function () {
  const filterButtons = document.querySelectorAll('.filter-btn');
  const searchInput = document.getElementById('news-search');
  const articles = document.querySelectorAll('.news-article');
  const countLabel = document.getElementById('news-count');
  const emptyState = document.getElementById('news-empty');

  let activeCategory = 'todas';

  function applyFilters() {
    const query = searchInput.value.trim().toLowerCase();
    let visibleCount = 0;

    articles.forEach(function (article) {
      const matchesCategory = activeCategory === 'todas' || article.dataset.category === activeCategory;
      const matchesSearch = query === '' || article.dataset.title.includes(query);
      const isVisible = matchesCategory && matchesSearch;

      article.hidden = !isVisible;
      if (isVisible) visibleCount++;
    });

    countLabel.textContent = 'Mostrando ' + visibleCount + ' de ' + articles.length + ' noticias';
    emptyState.hidden = visibleCount !== 0;
  }

  filterButtons.forEach(function (button) {
    button.addEventListener('click', function () {
      filterButtons.forEach(function (b) { b.setAttribute('aria-pressed', 'false'); });
      button.setAttribute('aria-pressed', 'true');
      activeCategory = button.dataset.category;
      applyFilters();
    });
  });

  searchInput.addEventListener('input', applyFilters);

  applyFilters();
});
