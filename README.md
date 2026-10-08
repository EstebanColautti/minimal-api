# Minimal API — Jenkins local

Proyecto de las 12 actividades incrementales de Jenkins, creado en Fedora 44 WSL.

## Acceso y agentes

- Jenkins: http://localhost:8080/job/minimal-api/
- Multibranch Pipeline: `minimal-api`; fuente GitHub `https://github.com/EstebanColautti/minimal-api.git`.
- Compilación: `build-agent`, etiquetas `podman build-agent`; .NET 10, Git y Podman remoto.
- Despliegue: `deploy-agent`, etiqueta `deploy-agent`; Git, curl y kubectl v1.36.3.
- Ambos agentes usan workspaces separados en `/home/jenkins/agent`.
- Registro: `localhost:5000`, accesible solamente desde el equipo y las redes de contenedores.
- Contextos Kubernetes: `kind-dev`, `kind-qa`, `kind-prd`.

El nombre `build-agent` se conserva por la última indicación del usuario. La etiqueta `build-agent` es la que selecciona el pipeline.

## Ejecutar

Desde Fedora, en `/home/vegamp4/minimal-api-pipeline`:

```bash
git add .
git commit -m 'Describe el cambio'
git push origin main
```

En Jenkins, ejecutar **Scan Multibranch Pipeline Now**. `origin` es `https://github.com/EstebanColautti/minimal-api.git`. La copia bare local se conserva como respaldo.

Para validación de una rama sin modificar los clústeres:

```bash
git switch -c feature/mi-cambio
git push origin feature/mi-cambio
```

El pipeline usa `checkout scm`, de modo que cada agente recibe la revisión exacta seleccionada por Jenkins. Solo `main` empaqueta, publica y despliega. El tag `git-<SHA>` identifica el código; los números de build identifican ejecuciones. Dos builds del mismo commit conservan el mismo tag. `latest` no permite demostrar qué revisión se promovió.

## Despliegue y verificación

```bash
./scripts/deploy.sh kind-dev dev localhost:5000/minimal-api:git-<SHA>
./scripts/test-environment.sh kind-dev 8081
./scripts/test-environment.sh kind-qa 8082
./scripts/test-environment.sh kind-prd 8083 --read-only
```

Los puertos de smoke tests son port-forwards dentro del agente de despliegue. `localhost` allí refiere a ese agente; el script abre y cierra el port-forward antes y después de la prueba.

Cada entorno tiene PostgreSQL persistente. El Job de migración crea la tabla de todos de forma idempotente, antes de esperar el rollout de la API. QA incorpora una configuración `ASPNETCORE_ENVIRONMENT=QA` en su overlay.

La misma imagen se promueve dev → QA → aprobación humana → producción local. La verificación de producción es de solo lectura. Los smoke tests de dev y QA eliminan los todos que crean.

## Ejercicios controlados

El parámetro Jenkins `EXERCISE` permite inyectar un fallo en una ejecución local:

| Valor | Fallo esperado | Recuperación |
|---|---|---|
| `compile` | Build | Ejecutar de nuevo con `none`; la modificación solo ocurre en el workspace. |
| `unit` | Unit Test | Ejecutar con `none`; revisar el TRX archivado. |
| `registry` | Publish Image | El post vuelve a iniciar registry; ejecutar con `none`. |
| `migration` | Deploy Dev | Corregir y volver a aplicar la migración; revisar logs del Job. |
| `readiness` | Deploy Dev | Restaurar el probe con el overlay y esperar el rollout. |
| `smoke` | Test Dev | Restablecer la respuesta correcta y redesplegar. |
| `qa` | Test QA | Restablecer la respuesta correcta en QA y repetir. |
| `production-rollout` | Deploy Production | Requiere aprobación; restaurar probe o hacer rollback. |

Los fallos de comportamiento cambian la respuesta de la API mientras la readiness permanece saludable. El test HTTP debe detectar la diferencia. La aprobación puede rechazarse o expirar después de 10 minutos; en ambos casos la etapa de producción se omite.

Rollback de aplicación:

```bash
kubectl --context kind-prd -n minimal-api rollout undo deployment/api
kubectl --context kind-prd -n minimal-api rollout status deployment/api
```

Un rollback de la aplicación no revierte automáticamente las migraciones de base de datos. Evaluar compatibilidad de esquema antes de retroceder.

## Evidencias y limpieza

Jenkins conserva `TestResults/unit-tests.trx` y `deployment-summary.txt` como artefactos. El resumen incluye commit, imagen, URL del build y resultados de dev, QA y producción. Los workspaces y archivos OCI temporales se limpian al terminar.

`activities/02.Jenkinsfile` a `12.Jenkinsfile` y los commits de cada actividad muestran la evolución. Las credenciales de Jenkins y Kubernetes están fuera del repositorio. El kubeconfig de despliegue se monta de solo lectura y sus permisos están limitados al namespace `minimal-api`, más lectura de ese namespace.

## GitHub

Repositorio: https://github.com/EstebanColautti/minimal-api. Jenkins obtiene el código desde GitHub. Los snapshots incrementales están en `activities/`; el historial original local se conserva como respaldo.

## Reinicio

WSL debe estar iniciado para acceder a Jenkins. `dev_container_net` se dejó detenido porque ocupa el puerto 5000 que necesita registry. No iniciarlo mientras ese puerto esté reservado por registry.

Local feature branch used to verify CI without deployment.

## Actualización del documento (2026-09-30)

La imagen de compilación también se define en `Container.build-agent`, conforme al documento actualizado:

```bash
podman build . -f Container.build-agent -t build_agent_img
./scripts/infrastructure/start-build-agent.sh
```

El nodo se conserva como `build-agent` con etiqueta `build-agent`, por la última indicación del usuario. El comando actualizado del documento omite el socket; este proyecto conserva el montaje del socket rootless y `CONTAINER_HOST`, necesarios para `podman load`, `tag` y `push`. El script usa el secret Podman existente y el volumen persistente del agente.

### Containerfiles proporcionados por el profesor

Se adoptaron los archivos `Containerfile.build-agent` y `Containerfile.deploy-agent` suministrados: Jenkins inbound agent Debian Trixie/JDK21, SDK .NET 10 de la imagen oficial y kubectl v1.36.3 de su imagen oficial. `Containerfile` y `Container.build-agent` son copias compatibles del build agent para los distintos nombres usados en el documento.

```bash
podman build -f Containerfile.build-agent -t build_agent_img:latest .
podman build -f Containerfile.deploy-agent -t jenkins_deploy_agent_img:latest .
./scripts/infrastructure/start-build-agent.sh
./scripts/infrastructure/start-deploy-agent.sh
```

Antes de arrancar el build agent: `systemctl --user enable --now podman.socket`. En WSL se habilitó lingering para que los servicios de usuario puedan arrancar sin una sesión interactiva. El agente de despliegue se conecta además a la red `kind` para alcanzar los API servers.

## Actualización 2026-10-05

Buildah se añadió al build agent. Imágenes canónicas: `build-agent-img:latest` y `deploy-agent-img:latest`; nodos y contenedores: `build-agent` y `deploy-agent`. Ambos nodos aceptan solo jobs con su etiqueta.

El Job `migration` ejecuta `migrate` desde la misma imagen de la API que se despliega, con la conexión desde el Secret existente. El SQL va embebido en la imagen y es idempotente; se comprueba `/readyz`, se recrea el Job y se espera su resultado antes del rollout. El namespace y sus credenciales se preparan fuera del pipeline.

En esta instalación el kubeconfig restringido está en `~/.kube/deploy-config` y se monta como archivo de solo lectura. El `mkdir -p ~/.kube/config` del ejemplo produciría un directorio; se conserva el archivo válido existente. Los clústeres ya existen y se reutilizan.
