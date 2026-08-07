// Paso 5: Arrays, bucles y metodos del DOM

// Array de objetos con los ingredientes de la receta.
// Cada objeto guarda el nombre, la cantidad y la unidad de medida.
const ingredientes = [
  { nombre: "Platano verde", cantidad: 2, unidad: "unidades" },
  { nombre: "Queso fresco", cantidad: 1, unidad: "taza" },
  { nombre: "Chicharron o tocino", cantidad: 0.5, unidad: "taza" },
  { nombre: "Mantequilla", cantidad: 1, unidad: "cucharada" },
  { nombre: "Sal", cantidad: "—", unidad: "al gusto" },
];

// Obtenemos la tabla y su <tbody> para poder insertar filas en el.
const tabla = document.getElementById("tabla-ingredientes");
const cuerpoTabla = document.getElementById("cuerpo-ingredientes");

// Recorremos el array con un bucle for y por cada ingrediente
// insertamos una fila nueva usando el metodo insertRow() del DOM,
// y dentro de ella creamos las celdas con insertCell().
for (let i = 0; i < ingredientes.length; i++) {
  const ingrediente = ingredientes[i];
  const fila = cuerpoTabla.insertRow();

  const celdaNombre = fila.insertCell(0);
  const celdaCantidad = fila.insertCell(1);
  const celdaUnidad = fila.insertCell(2);

  celdaNombre.textContent = ingrediente.nombre;
  celdaCantidad.textContent = ingrediente.cantidad;
  celdaUnidad.textContent = ingrediente.unidad;
}

// Actualizamos el pie de la tabla con el total de ingredientes usando .length
const pieTabla = document.getElementById("pie-ingredientes");
pieTabla.textContent = "Total de ingredientes: " + ingredientes.length;