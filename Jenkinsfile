pipeline {

    agent any

    environment {
        AWS_REGION   = "us-east-1"
        CLUSTER_NAME = "devops-cluster"
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
                        sh 'terraform init -input=false -no-color'
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
                        sh 'terraform plan -input=false -no-color -out=tfplan'
                    }
                }
            }
        }

        stage('Terraform Apply') {
            // Removed: when { branch 'main' }
            // Branch detection is unreliable with SCM polling + detached HEAD.
            // Pipeline is already scoped to the main branch via the job config.
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    dir('terraform') {
                        sh 'terraform apply -input=false -no-color tfplan'
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
                        // -no-color prevents ANSI escape codes polluting the URL
                        def ecrRepo = sh(
                            returnStdout: true,
                            script: 'cd terraform && terraform output -no-color -raw ecr_repository_url'
                        ).trim()

                        sh """
                            aws ecr get-login-password --region ${env.AWS_REGION} \
                              | docker login --username AWS --password-stdin ${ecrRepo}

                            docker tag devops-app:${env.IMAGE_TAG} ${ecrRepo}:${env.IMAGE_TAG}
                            docker tag devops-app:${env.IMAGE_TAG} ${ecrRepo}:latest

                            docker push ${ecrRepo}:${env.IMAGE_TAG}
                            docker push ${ecrRepo}:latest
                        """

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
            sh "docker rmi devops-app:${env.BUILD_NUMBER} || true"
        }
    }
}