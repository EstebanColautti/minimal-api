# Minimal API

API de tareas desarrollada con ASP.NET Core y .NET 10. Incluye pruebas unitarias, migraciones de PostgreSQL y un pipeline de Jenkins para publicar y promover imágenes entre entornos Kubernetes.

## Requisitos

- .NET 10 SDK para compilar y ejecutar las pruebas.
- PostgreSQL para los datos de la API.
- Jenkins con agentes etiquetados `build-agent` y `deploy-agent`.
- Podman, Buildah y un registro de imágenes para el pipeline.
- Kubernetes, kubectl y overlays Kustomize para dev, QA y producción.

## Compilar y probar

```bash
dotnet restore
dotnet build --configuration Release --no-restore
dotnet test --configuration Release --no-build --logger trx
```

## Configuración y ejecución

Definir `ConnectionStrings__Todos` con la conexión a PostgreSQL. Las credenciales deben suministrarse mediante variables de entorno o Secrets; no se incluyen en el repositorio.

```bash
dotnet run --project src/Api -- migrate
dotnet run --project src/Api
```

La migración crea la tabla de tareas de forma idempotente.

## Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health/live` | Estado del proceso. |
| GET | `/health/ready` | Comprueba el acceso al esquema de PostgreSQL. |
| GET | `/todos` | Lista las tareas. |
| GET | `/todos/{id}` | Obtiene una tarea. |
| POST | `/todos` | Crea una tarea con un título de 1 a 200 caracteres. |
| DELETE | `/todos/{id}` | Elimina una tarea. |

## Pipeline de Jenkins

El `Jenkinsfile` usa `checkout scm` para compilar la revisión seleccionada por Jenkins.

- Todas las ramas y pull requests ejecutan compilación y pruebas unitarias.
- Solo `main` empaqueta y publica la imagen `minimal-api:git-<SHA>`.
- La misma imagen se promueve a dev y QA, con migraciones, rollout y pruebas HTTP.
- Producción requiere aprobación humana, con un tiempo máximo de 10 minutos.
- La comprobación de producción es de solo lectura.
- Se archivan resultados TRX y un resumen con commit, imagen y resultado por entorno.
- Los workspaces se limpian al finalizar.

Los agentes de compilación y despliegue tienen herramientas y workspaces separados. El agente de despliegue recibe el kubeconfig como archivo de solo lectura.

## Estructura

```text
src/Api/          API y comando de migración
tests/Api.Tests/  Pruebas unitarias
sql/             SQL de migración
k8s/             Manifiestos base y overlays
scripts/         Despliegue, pruebas e infraestructura
activities/      Versiones incrementales del Jenkinsfile
Jenkinsfile      Pipeline completo
```

## Ejercicios controlados

El parámetro `EXERCISE` permite simular fallos de compilación, pruebas, publicación, migración, readiness, comportamiento HTTP, QA y rollout de producción. Su valor normal es `none`.

Un fallo debe detener la promoción a los siguientes entornos. Un rollback del Deployment no revierte las migraciones de la base de datos.
