# Create all variables used in this Terraform run
variable "aws_bucket_name" {}
variable "aws_region_main" {
  default = "us-east-1"
}
variable "aws_region_replica" {
  default = "us-west-1"
}

# Use AWS credentials
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_access_secret_key}"
}

# Give Different aliases for aws regions
provider "aws" {
  alias  = "east"
  region = "us-east-1"
}
provider "aws" {
  alias  = "west-1"
  region = "us-west-1"
}

# Create replication role
resource "aws_iam_role" "replication" {
  name               = "tf-iam-role-replication-12345"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "replication" {
    name = "tf-iam-role-policy-replication-12345"
    policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.uploads.arn}"
      ]
    },
    {
      "Action": [
        "s3:GetObjectVersion",
        "s3:GetObjectVersionAcl"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.uploads.arn}/*"
      ]
    },
    {
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.replica.arn}/*"
    }
  ]
}
POLICY
}

resource "aws_iam_policy_attachment" "replication" {
    name = "tf-iam-role-attachment-replication-12345"
    roles = ["${aws_iam_role.replication.name}"]
    policy_arn = "${aws_iam_policy.replication.arn}"
}

# This is the replication bucket for uploads
resource "aws_s3_bucket" "replica" {
    provider = "aws.west"
    bucket   = "${var.aws_bucket_name}-replica-1"
    region   = "${var.aws_region_replica}"
    acl      = "privite"

    # Enable versioning so that files can be replicated
    versioning {
      enabled = true
    }

    # Remove old versions of images after 15 days
    lifecycle_rule {
        prefix = ""
        enabled = true

        noncurrent_version_expiration {
            days = 15
        }
    }
}

# This is the main s3 bucket for uploads
resource "aws_s3_bucket" "uploads" {
    provider = "aws.east"
    bucket = "${var.aws_bucket_name}"
    acl = "privite"
    region = "${var.aws_region_main}"

    # Enable versioning so that files can be replicated
    versioning {
      enabled = true
    }

    # Remove old versions after 15 days, these shouldn't happen that often because
    # humanmade/s3-uploads will rename files which have same name
    lifecycle_rule {
        prefix = ""
        enabled = true

        noncurrent_version_expiration {
            days = 15
        }
    }

    replication_configuration {
        role = "${aws_iam_role.replication.arn}"
        rules {
            id     = "replica"
            prefix = ""
            status = "Enabled"

            destination {
                bucket        = "${aws_s3_bucket.replica.arn}"
                storage_class = "STANDARD"
            }
        }
    }
}

resource "aws_iam_user" "uploads_user" {
    name = "${var.aws_bucket_name}-user"
}

resource "aws_iam_access_key" "uploads_user" {
    user = "${aws_iam_user.uploads_user.name}"
}

resource "aws_iam_user_policy" "wp_uploads_policy" {
    name = "WordPress-S3-Uploads"
    user = "${aws_iam_user.uploads_user.name}"

    # S3 policy from humanmade/s3-uploads for WordPress uploads
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1392016154000",
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation",
        "s3:GetBucketPolicy",
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": [
        "arn:aws:s3:::${aws_s3_bucket.uploads.bucket}/*"
      ]
    },
    {
      "Sid": "AllowRootAndHomeListingOfBucket",
      "Action": ["s3:ListBucket"],
      "Effect": "Allow",
      "Resource": ["arn:aws:s3:::${aws_s3_bucket.uploads.bucket}"],
      "Condition":{"StringLike":{"s3:prefix":["*"]}}
    }
  ]
}
EOF
}

# These output the created access keys and bucket name
output "s3-bucket-name" {
    value = "${var.aws_bucket_name}"
}

output "s3-user-access-key" {
    value = "${aws_iam_access_key.uploads_user.id}"
}

output "s3-user-secret-key" {
    value = "${aws_iam_access_key.uploads_user.secret}"
}
