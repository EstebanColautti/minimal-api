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
    }
    stages {        stage('Checkout') {
            steps {
                script {
                    def revision = checkout scm
                    env.SOURCE_COMMIT = revision.GIT_COMMIT
                    env.DEV_RESULT = 'NOT_RUN'
                    env.QA_RESULT = 'NOT_RUN'
                    env.PRD_RESULT = 'NOT_RUN'
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
            when { branch 'main' }
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
            when { branch 'main' }
            steps {
                sh '''
                    if [ "$EXERCISE" = registry ]; then podman stop registry; fi
                    podman push --tls-verify=false "$IMAGE"
                    podman image inspect "$IMAGE"
                '''
            }
        }
        stage('Deploy Dev') {
            when { beforeAgent true; branch 'main' }
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
        stage('Test Dev') {
            when { beforeAgent true; branch 'main' }
            agent { label 'deploy-agent' }
            steps {
                checkout scm
                sh '''
                    if [ "$EXERCISE" = smoke ]; then
                        kubectl --context kind-dev -n minimal-api set env deployment/api BEHAVIOR_REGRESSION=true
                        kubectl --context kind-dev -n minimal-api rollout status deployment/api --timeout=120s
                    fi
                    ./scripts/test-environment.sh kind-dev 8081
                '''
            }
            post { success { script { env.DEV_RESULT = 'VERIFIED' } }; failure { script { env.DEV_RESULT = 'TEST_FAILED' } }; always { cleanWs() } }
        }
        stage('Deploy QA') {
            when { beforeAgent true; branch 'main' }
            agent { label 'deploy-agent' }
            steps { checkout scm; sh './scripts/deploy.sh kind-qa qa "$IMAGE"' }
            post { success { script { env.QA_RESULT = 'DEPLOYED' } }; failure { script { env.QA_RESULT = 'FAILED' } }; always { cleanWs() } }
        }
        stage('Test QA') {
            when { beforeAgent true; branch 'main' }
            agent { label 'deploy-agent' }
            steps {
                checkout scm
                sh '''
                    if [ "$EXERCISE" = qa ]; then
                        kubectl --context kind-qa -n minimal-api set env deployment/api BEHAVIOR_REGRESSION=true
                        kubectl --context kind-qa -n minimal-api rollout status deployment/api --timeout=120s
                    fi
                    ./scripts/test-environment.sh kind-qa 8082
                '''
            }
            post { success { script { env.QA_RESULT = 'VERIFIED' } }; failure { script { env.QA_RESULT = 'TEST_FAILED' } }; always { cleanWs() } }
        }
        stage('Approve Production') {
            when { branch 'main' }
            options { timeout(time: 10, unit: 'MINUTES') }
            steps {
                input id: 'production', message: "Deploy ${env.IMAGE} to the local kind-prd cluster?", ok: 'Deploy'
                echo 'Production deployment approved'
            }
        }
        stage('Deploy Production') {
            when { beforeAgent true; branch 'main' }
            agent { label 'deploy-agent' }
            steps {
                checkout scm
                sh '[ "$EXERCISE" != production-rollout ] || export FAIL_READINESS=1; ./scripts/deploy.sh kind-prd prd "$IMAGE"'
            }
            post { success { script { env.PRD_RESULT = 'DEPLOYED' } }; failure { script { env.PRD_RESULT = 'FAILED' } }; always { cleanWs() } }
        }
        stage('Verify Production') {
            when { beforeAgent true; branch 'main' }
            agent { label 'deploy-agent' }
            steps { checkout scm; sh './scripts/test-environment.sh kind-prd 8083 --read-only' }
            post { success { script { env.PRD_RESULT = 'VERIFIED' } }; failure { script { env.PRD_RESULT = 'TEST_FAILED' } }; always { cleanWs() } }
        }
    }
    post {
        success { echo "Successfully promoted ${env.IMAGE ?: env.GIT_COMMIT}" }
        unsuccessful { echo "Pipeline failed for ${env.SOURCE_COMMIT}" }
        always {
            script {
                writeFile file: 'deployment-summary.txt', text: "Git commit: ${env.SOURCE_COMMIT}\nImage: ${env.IMAGE ?: 'NOT_PACKAGED'}\nBuild: ${env.BUILD_URL}\nDev: ${env.DEV_RESULT}\nQA: ${env.QA_RESULT}\nProduction: ${env.PRD_RESULT}\nResult: ${currentBuild.currentResult}\n"
            }
            archiveArtifacts artifacts: 'TestResults/**/*,deployment-summary.txt', allowEmptyArchive: true
            script { if (params.EXERCISE == 'registry') { sh 'podman start registry' } }
            cleanWs()
        }
    }
}
