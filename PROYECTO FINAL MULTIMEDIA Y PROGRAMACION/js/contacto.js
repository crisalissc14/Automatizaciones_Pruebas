// GROUNDS — contacto.js
// Validación del formulario de contacto (simulado, sin backend).

document.addEventListener('DOMContentLoaded', function () {
  const form = document.getElementById('contact-form');
  if (!form) return;

  const success = document.getElementById('contact-success');
  const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  form.addEventListener('submit', function (event) {
    event.preventDefault();

    const name = document.getElementById('contact-name');
    const email = document.getElementById('contact-email');
    const message = document.getElementById('contact-message');

    const errors = {
      'error-name': '',
      'error-email': '',
      'error-message': ''
    };
    let isValid = true;

    if (name.value.trim() === '') {
      errors['error-name'] = 'Ingresa tu nombre.';
      isValid = false;
    }

    if (email.value.trim() === '') {
      errors['error-email'] = 'Ingresa un correo electrónico.';
      isValid = false;
    } else if (!emailPattern.test(email.value.trim())) {
      errors['error-email'] = 'El correo no tiene un formato válido.';
      isValid = false;
    }

    if (message.value.trim() === '') {
      errors['error-message'] = 'Escribe un mensaje.';
      isValid = false;
    }

    Object.keys(errors).forEach(function (id) {
      document.getElementById(id).textContent = errors[id];
    });

    if (!isValid) {
      if (success) success.hidden = true;
      return;
    }

    if (success) success.hidden = false;
    form.reset();
  });
});
