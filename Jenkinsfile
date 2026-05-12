pipeline {
    agent any

    environment {
        AWS_REGION   = "us-east-1"
        CLUSTER_NAME = "devops-cluster"
        ECR_REPO     = sh(returnStdout: true, script: '''
            cd terraform && terraform output -raw ecr_repository_url
        ''').trim()
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
                        // Safe to run on every build — no-op if infra already matches
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
                        // Idempotent: skips if infra already exists and matches
                        sh 'terraform apply -input=false tfplan'
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh "docker build -t devops-app:${IMAGE_TAG} ."
            }
        }

        stage('Push to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} \
                          | docker login --username AWS --password-stdin ${ECR_REPO}

                        docker tag devops-app:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}
                        docker tag devops-app:${IMAGE_TAG} ${ECR_REPO}:latest

                        docker push ${ECR_REPO}:${IMAGE_TAG}
                        docker push ${ECR_REPO}:latest
                    """
                }
            }
        }

        stage('Configure EKS Access') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    sh "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}"
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh """
                    sed -i 's|:latest|:${IMAGE_TAG}|g' k8s-deployment.yaml

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
                sh """
                    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
                """
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    kubectl get pods
                    kubectl get svc
                    kubectl get hpa
                """
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
            sh "docker rmi devops-app:${IMAGE_TAG} || true"
        }
    }
}