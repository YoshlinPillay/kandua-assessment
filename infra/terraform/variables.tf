variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "juan"
}

variable "region" {
  description = "Infrastructure region (D-021: Cape Town)."
  type        = string
  default     = "af-south-1"
}

variable "bedrock_region" {
  description = "Region for Bedrock inference (D-021: af-south-1 has no open-weight models)."
  type        = string
  default     = "us-east-1"
}

variable "bedrock_model_id" {
  description = "Chat model chosen by the golden-question bake-off (D-027)."
  type        = string
  default     = "openai.gpt-oss-120b-1:0"
}

variable "instance_type" {
  description = "One EC2 host runs the whole stack (D-029). c7i-flex.large is the largest Free-plan-eligible type (4 GB); measured idle use is ~2.3 GB, plus a 4 GB swap file for build/pipeline peaks (D-032)."
  type        = string
  default     = "c7i-flex.large"
}

variable "db_instance_class" {
  description = "RDS Postgres instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_public_cidrs" {
  description = "CIDRs allowed to reach Postgres. Public by human decision (reviewers get read-only creds); TLS is enforced."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "github_repo" {
  description = "owner/name of the (public) GitHub repository the host deploys from."
  type        = string
  default     = "YoshlinPillay/kandua-assessment"
}

variable "git_ref" {
  description = "Branch or tag the host deploys."
  type        = string
  default     = "main"
}

variable "alert_email" {
  description = "Email for AWS Budgets alerts. Set in terraform.tfvars (gitignored), never committed."
  type        = string
}

variable "monthly_budget_usd" {
  description = "AWS Budgets monthly limit (alerts at 80% actual and 100% forecast)."
  type        = number
  default     = 20
}

variable "admin_email" {
  description = "Email for the human's Lightdash admin login (an invite link is generated on deploy)."
  type        = string
}
