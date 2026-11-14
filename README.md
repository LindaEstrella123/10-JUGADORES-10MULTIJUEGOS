# 🎮 10 JUGADORES, 10 DESAFÍOS

Juego web multijugador de hasta 10 personas. GitHub Pages publica la página y Supabase almacena el estado de las salas y notifica cambios en tiempo real.

## Archivos
- `index.html`: pantallas del juego.
- `style.css`: diseño adaptable a celulares y computadoras.
- `script.js`: minijuegos y reglas.
- `supabase-config.js`: URL y publishable key del proyecto.
- `supabase-adapter.js`: conexión de la aplicación con Supabase.
- `supabase-setup.sql`: crea la tabla y activa Realtime.

## 1. Configurar Supabase
1. Abre https://supabase.com/dashboard y entra a tu proyecto.
2. Abre **SQL Editor** → **New query**.
3. Abre `supabase-setup.sql`, copia todo su contenido, pégalo en el editor y pulsa **Run**.
4. En **Authentication** → **Sign In / Providers**, activa **Anonymous** si tu panel ofrece ese proveedor. El juego usa inicio de sesión anónimo.
5. En **Project Settings** → **API Keys**, copia tu **Publishable key**. En **Data API** copia el Project URL.
6. Comprueba que ambos valores estén en `supabase-config.js`. El Project URL debe terminar en `.supabase.co`, sin `/rest/v1/`.

## 2. Seguridad: lee antes de publicar
Esta versión usa una política inicial abierta para facilitar la prueba de las salas. El código de 6 caracteres no es una contraseña: una persona que lo conozca podría leer o modificar los datos de esa sala. Úsalo para partidas casuales y no guardes datos personales. Para un juego público competitivo se debe reemplazar esta política por validación del lado del servidor (por ejemplo, Edge Functions/RPC) antes de compartirlo ampliamente. Nunca pongas una `secret` key ni `service_role` key en los archivos del navegador.

## 3. Probar
1. Abre `index.html` desde un servidor local o GitHub Pages (no todos los navegadores permiten todas las funciones desde `file://`).
2. Crea una sala, copia el código y abre el enlace en otro dispositivo o ventana privada.
3. Escribe un nombre, introduce el código y entra.
4. Con al menos 2 jugadores, el anfitrión puede iniciar la partida.

## 4. Publicar en GitHub Pages
1. Sube todos los archivos de esta carpeta a la raíz de tu repositorio (donde está `index.html`).
2. En GitHub abre **Settings** → **Pages**.
3. En **Build and deployment**, elige **Deploy from a branch**, rama `main` y carpeta `/ (root)`. Pulsa **Save**.
4. Espera a que aparezca **Visit site**.
5. Comparte el enlace público con los jugadores.

## Notas técnicas
- Realtime notifica cambios en la fila de cada sala.
- El estado completo de cada sala se almacena como JSON en `game_rooms.data`.
- La sincronización está pensada para partidas casuales y salas pequeñas. La escritura del estado completo puede producir conflictos si varias personas escriben simultáneamente; para producción se recomienda normalizar jugadores/respuestas en tablas y validar acciones en servidor.
