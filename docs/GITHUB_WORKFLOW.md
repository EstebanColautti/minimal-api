# Flujo GitHub y Jenkins

Repositorio: https://github.com/EstebanColautti/minimal-api

1. Crear una rama feature y subir el cambio a GitHub.
2. Abrir un pull request hacia main.
3. En Jenkins, ejecutar Scan Multibranch Pipeline Now.
4. Verificar Build y Unit Test en la rama y en PR-1: no deben empaquetar, publicar ni desplegar.
5. Fusionar después de que las pruebas pasen.
6. Volver a escanear main: publica localhost:5000/minimal-api:git-<SHA>, migra y prueba dev y QA.
7. Aprobar manualmente el despliegue a producción local; verificar sin modificar datos.

Jenkins local no tiene una URL pública para recibir webhooks de GitHub. Se usa el escaneo manual.
Las credenciales de Kubernetes y los secretos de los agentes quedan fuera de Git.
El historial local anterior permanece en la rama backup/local-before-github y el remoto local-backup.
