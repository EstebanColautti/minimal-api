pipeline {
    agent { label 'build-agent' }
    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '40', artifactNumToKeepStr: '40'))
    }
    parameters {
        choice(name: 'EXERCISE', choices: ['none', 'compile', 'unit', 'registry', 'migration', 'readiness', 'smoke', 'qa', 'production-rollout'], description: 'Controlled local failure exercise; none is the normal pipeline')
    }
    environment {
        CONFIGURATION = 'Release'
        REGISTRY = 'localhost:5000'
        IMAGE_NAME = 'minimal-api'
        DEV_RESULT = 'NOT_RUN'
        QA_RESULT = 'NOT_RUN'
        PRD_RESULT = 'NOT_RUN'
    }
    stages {        stage('Checkout') {
            steps {
                script {
                    def revision = checkout scm
                    env.SOURCE_COMMIT = revision.GIT_COMMIT
                }
                sh 'git log -1 --oneline'
            }
        }
        stage('Build') {
            steps {
                sh '''
                    if [ "$EXERCISE" = compile ]; then printf 'deliberate syntax error' > src/Api/InjectedFailure.cs; fi
                    dotnet restore
                    dotnet build --configuration "$CONFIGURATION" --no-restore
                '''
            }
        }
        stage('Unit Test') {
            steps {
                sh '''
                    rm -rf TestResults
                    if [ "$EXERCISE" = unit ]; then
                        printf 'public class InjectedFailure { [Xunit.Fact] public void Fails() => Xunit.Assert.True(false); }' > tests/Api.Tests/InjectedFailure.cs
                        dotnet build --configuration "$CONFIGURATION" --no-restore
                    fi
                    dotnet test --configuration "$CONFIGURATION" --no-build --logger "trx;LogFileName=unit-tests.trx" --results-directory TestResults
                '''
            }
            post { always { archiveArtifacts artifacts: 'TestResults/**/*', allowEmptyArchive: true } }
        }
        stage('Version') {
            steps {
                script {
                    env.SHORT_COMMIT = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG = "git-${env.SHORT_COMMIT}"
                    env.IMAGE = "${env.REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                }
                echo "Release image: ${env.IMAGE}"
            }
        }
        stage('Package Image') {
            steps {
                sh '''
                    rm -rf out
                    mkdir -p out
                    dotnet publish src/Api --configuration "$CONFIGURATION" --no-build -p:PublishProfile=DefaultContainer -p:ContainerRepository="$IMAGE_NAME" -p:ContainerImageTag="$IMAGE_TAG" -p:ContainerArchiveOutputPath="$WORKSPACE/out/minimal-api.tar"
                    podman load --input out/minimal-api.tar
                    podman tag "$IMAGE_NAME:$IMAGE_TAG" "$IMAGE"
                '''
            }
        }
        stage('Publish Image') {
            steps {
                sh '''
                    if [ "$EXERCISE" = registry ]; then podman stop registry; fi
                    podman push --tls-verify=false "$IMAGE"
                    podman image inspect "$IMAGE"
                '''
            }
        }
        stage('Deploy Dev') {
            agent { label 'deploy-agent' }
            steps {
                checkout scm
                sh '''
                    export FAIL_MIGRATION=0 FAIL_READINESS=0
                    [ "$EXERCISE" != migration ] || export FAIL_MIGRATION=1
                    [ "$EXERCISE" != readiness ] || export FAIL_READINESS=1
                    ./scripts/deploy.sh kind-dev dev "$IMAGE"
                '''
            }
            post { success { script { env.DEV_RESULT = 'DEPLOYED' } }; failure { script { env.DEV_RESULT = 'FAILED' } }; always { cleanWs() } }
        }

    }
}
