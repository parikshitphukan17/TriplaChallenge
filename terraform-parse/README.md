<div align="center">
   <img src="/img/logo.svg?raw=true" width=600 style="background-color:white;">
</div>

# SRE Technical Take-Home Assignment : Terraform-Parse (Terraform + Helm)

Welcome to the Tripla SRE take-home assignment! 🧑‍💻 This exercise is designed to simulate a real-world scenario where you'll tackle challenges across infrastructure, platform engineering, and automation.

⚠️ **Before you begin**, please review the main [FAQ](/README.md#frequently-asked-questions). It contains important information, **including our specific guidelines on how to submit your solution.**

## Repo structure
- `terraform/` : Terraform code (intentionally imperfect) for an EKS cluster and an S3 bucket .
- `helm/` : A Helm chart (intentionally buggy) that deploys an API service .

## Candidate Tasks
### Create `Terraform-Parse` Service
1. Please Create a backend service to render an API request into terraform file
   (You can use any language/framework you’re comfortable with (e.g., Python/Flask, Node/Express, Go/Fiber). Keep it minimal.)
2. Service needs to receive rest api request (`POST` method) with certain payload.
    ```
    {
    "payload":{
        "properties":{
            "aws-region":"eu-west-1",
            "acl":"private",
            "bucket-name": "tripla-bucket"
        }
    }
    }
    ```
3. Parse this payload and and programmatically generate a valid Terraform configuration file (.tf) for S3 bucket creation. Resources created should at least include:
    - provider
    - aws_s3_bucket
    - aws_s3_bucket_acl
4. Please put your code to folder `terraform_parse_service`

### Infrastructure (Terraform)
5. You have provided a set of Terraform code to create an EKS. Please review the code, identify issues or design flaws.
6. Adjust or refactor be safe and maintainable for multiple environments.

### Platform (Kubernetes + Helm)
7. You are provided a set of Helm code. Please review and deploy `Terraform-Parse` service into a Kubernetes cluster using the provided Helm setup (local kind/minikube is fine).
8. Debug and fix if you find services don't route properly.
9. Improve other aspects as you see fit.

## Minimum Deliverables
1.  A link to your Git repository containing the complete solution.
2.  Clear instructions in the `README.md` on how to build, test, and run your service.
3. `NOTES.md` with explanations for API service creation, Terraform fixes, Helm fixes, multi-env thoughts, and any AI usage.
