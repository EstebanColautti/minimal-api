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

    }
}
