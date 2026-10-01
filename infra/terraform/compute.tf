locals {
  # sslip.io maps <ip-with-dashes>.sslip.io to that IP, so Caddy can get real Let's Encrypt certificates
  # without buying a domain. Subdomains (lightdash.<ip>.sslip.io) resolve the same way.
  domain = "${replace(aws_eip.app.public_ip, ".", "-")}.sslip.io"
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---- Instance role: least privilege for exactly what the host does ------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.project}-app-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Session Manager instead of SSH
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadDeployParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"]
  }
  statement {
    sid       = "ReadRdsMasterSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.warehouse.master_user_secret[0].secret_arn]
  }
  statement {
    sid       = "LightdashResultsBucket"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.lightdash.arn, "${aws_s3_bucket.lightdash.arn}/*"]
  }
  statement {
    sid       = "InvokeChatModelOnly"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["arn:aws:bedrock:${var.bedrock_region}::foundation-model/${var.bedrock_model_id}"]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.project}-app-host"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-app-host"
  role = aws_iam_role.app.name
}

# ---- The host ------------------------------------------------------------------------------------------------
resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # containers (one extra hop) can use the instance role
  }

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
  }

  # First boot only: install Docker, clone the repo, run deploy/aws/deploy.sh. Later deploys go through SSM
  # (`make tf-deploy` or the deploy workflow), so changing this script doesn't replace the host.
  user_data = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    project     = var.project
    region      = var.region
    github_repo = var.github_repo
    git_ref     = var.git_ref
  })

  tags = { Name = "${var.project}-app-host" }

  lifecycle {
    ignore_changes = [ami, user_data] # AMI updates and bootstrap edits must not silently replace the host
  }

  depends_on = [aws_ssm_parameter.app, aws_ssm_parameter.config, aws_ssm_parameter.lightdash_pat]
}

resource "aws_eip" "app" {
  domain = "vpc"
  tags   = { Name = "${var.project}-app-host" }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}
