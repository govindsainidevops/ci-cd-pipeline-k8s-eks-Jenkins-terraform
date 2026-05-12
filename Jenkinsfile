pipeline {

    agent any

    environment {
        AWS_REGION   = "us-east-1"
        CLUSTER_NAME = "devops-cluster"
        // Do NOT call terraform output here — Terraform may not be initialised yet
        // ECR_REPO is resolved lazily in the Push stage instead
        IMAGE_TAG    = "${env.BUILD_NUMBER}"
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/govindsainidevops/ci-cd-pipeline-k8s-eks-Jenkins-terraform.git'
            }
        }

        stage('Terraform Init & Validate') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    dir('terraform') {
                        sh 'terraform init -input=false'
                        sh 'terraform fmt -check'
                        sh 'terraform validate'
                    }
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    dir('terraform') {
                        sh 'terraform plan -input=false -out=tfplan'
                    }
                }
            }
        }

        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    dir('terraform') {
                        sh 'terraform apply -input=false tfplan'
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh "docker build -t devops-app:${env.IMAGE_TAG} ."
            }
        }

        stage('Push to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    script {
                        // Resolve ECR URL here — after terraform apply has run
                        def ecrRepo = sh(
                            returnStdout: true,
                            script: 'cd terraform && terraform output -raw ecr_repository_url'
                        ).trim()

                        sh """
                            aws ecr get-login-password --region ${env.AWS_REGION} \
                              | docker login --username AWS --password-stdin ${ecrRepo}

                            docker tag devops-app:${env.IMAGE_TAG} ${ecrRepo}:${env.IMAGE_TAG}
                            docker tag devops-app:${env.IMAGE_TAG} ${ecrRepo}:latest

                            docker push ${ecrRepo}:${env.IMAGE_TAG}
                            docker push ${ecrRepo}:latest
                        """

                        // Store for downstream stages
                        env.ECR_REPO = ecrRepo
                    }
                }
            }
        }

        stage('Configure EKS Access') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    sh "aws eks update-kubeconfig --region ${env.AWS_REGION} --name ${env.CLUSTER_NAME}"
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh """
                    sed -i 's|:latest|:${env.IMAGE_TAG}|g' k8s-deployment.yaml

                    kubectl apply -f k8s-deployment.yaml
                    kubectl apply -f hpa.yaml
                    kubectl apply -f prometheus-deployment.yaml
                    kubectl apply -f grafana-deployment.yaml

                    kubectl rollout status deployment/devops-app --timeout=120s
                """
            }
        }

        stage('Install Metrics Server') {
            steps {
                sh 'kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml'
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    kubectl get pods
                    kubectl get svc
                    kubectl get hpa
                '''
            }
        }
    }

    post {
        success {
            echo "✅ Deployment successful! Build #${env.BUILD_NUMBER}"
        }
        failure {
            echo "❌ Deployment failed at stage: ${env.STAGE_NAME}"
        }
        always {
            // Use env.BUILD_NUMBER directly — IMAGE_TAG may not be set if pipeline failed early
            sh "docker rmi devops-app:${env.BUILD_NUMBER} || true"
        }
    }
}