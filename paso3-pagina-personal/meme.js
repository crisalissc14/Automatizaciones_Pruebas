// Paso 4: variables con la informacion de mi meme favorito
const memeNombre = "Punch";
const memeRazon = "siempre me representa cuando ando bajoneada y solo quiero comer pizza";
const memeAnio = 2026;

// Concateno las 3 variables en una sola oracion legible.
// La frase se arma en ingles porque la consigna del ejercicio pide ese patron exacto:
// "The first time I saw [nombre] was in [anio] and I like it because [razon]."
const memeOracion =
  "The first time I saw " + memeNombre + " was in " + memeAnio +
  " and I like it because " + memeRazon + ".";

// Busco los elementos del HTML por su id y les asigno el texto generado
const tituloMeme = document.getElementById("meme-name");
const parrafoMeme = document.getElementById("meme-sentence");

tituloMeme.textContent = memeNombre;
parrafoMeme.textContent = memeOracion;
