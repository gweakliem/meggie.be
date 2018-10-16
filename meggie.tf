provider "aws" {
  region = "us-west-2"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "meg"
}

variable "environment" {
  default = "production"
}

variable "mp3_bucket" {
  default = "meggie-mp3-bucket"
}

variable "www_bucket" {
  default = "meggie.be"
}

locals {
  global_tags = {
    Environment = "${var.environment}"
    Org         = "meggie"
  }
}

data "aws_s3_bucket" "meggie_website_bucket" {
  bucket = "${var.www_bucket}"
}
data "aws_s3_bucket" "meggie_mp3_bucket" {
  bucket = "${var.mp3_bucket}"
}

// TODO: this must be a better way to manage static resources than one at a time
resource "aws_s3_bucket_object" "index" {
  bucket = "${data.aws_s3_bucket.meggie_website_bucket.bucket}"
  key    = "index.html"
  source = "website/index.html"
  acl = "public-read"
  content_type = "text/html"
}

resource "aws_s3_bucket_object" "css" {
  bucket = "${data.aws_s3_bucket.meggie_website_bucket.bucket}"
  key    = "styles.css"
  source = "website/styles.css"
  acl = "public-read"
  content_type = "text/css"
}

resource "aws_s3_bucket_object" "scripts" {
  bucket = "${data.aws_s3_bucket.meggie_website_bucket.bucket}"
  key    = "scripts.js"
  source = "website/scripts.js"
  acl = "public-read"
  content_type = "text/javascript"
}


resource "aws_dynamodb_table" "meggie_db" {
  name           = "LearnAboutAnimals"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "Id"

  attribute {
    name = "Id"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled = false
  }

  tags = "${merge(local.global_tags,map("Name", "meggie_db"))}"
}

resource "aws_sns_topic" "new_posts" {
  name = "meggie_new_posts"
}

// TODO: refactor to separate policies for permissions necessary for each lambda
resource "aws_iam_policy" "lambda_policy" {
  name        = "meggie_lambda_policy"
  path        = "/"
  description = "Lambda Execution Policy for Meggie Lambdas"

  policy =  "${file("lambda-policy.json")}"
}

resource "aws_iam_role" "lambda_role" {
  name = "meggie_lambda_role"

  assume_role_policy = <<EOF
{ "Version":"2012-10-17",
    "Statement":[
      {"Effect":"Allow",
       "Principal":{
         "Service":"lambda.amazonaws.com"},
        "Action":"sts:AssumeRole"}
    ]}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
    role       = "${aws_iam_role.lambda_role.name}"
    policy_arn = "${aws_iam_policy.lambda_policy.arn}"
}

data "archive_file" "new_posts_pkg" {
  type        = "zip"
  source_file = "${path.module}/lambda/newposts.py"
  output_path = "${path.module}/target/newposts.zip"
}
resource "aws_lambda_function" "new_posts" {
  filename         = "${data.archive_file.new_posts_pkg.output_path}"
  function_name    = "Meggie_NewPosts"
  role             = "${aws_iam_role.lambda_role.arn}"
  handler          = "lambda_handler"
  source_code_hash = "${data.archive_file.new_posts_pkg.output_base64sha256}"
  runtime          = "python3.6"
  tags = "${merge(local.global_tags,map("Name", "new_posts"))}"

  environment {
    variables = {
      DB_TABLE_NAME = "${aws_dynamodb_table.meggie_db.name}"
      SNS_TOPIC = "${aws_sns_topic.new_posts.arn}"
    }
  }
}

data "archive_file" "get_posts_pkg" {
  type = "zip"
  source_file = "${path.module}/lambda/getposts.py"
  output_path = "${path.module}/target/getposts.zip"
}
resource "aws_lambda_function" "get_posts" {
  filename         = "${data.archive_file.get_posts_pkg.output_path}"
  function_name    = "Meggie_GetPosts"
  role             = "${aws_iam_role.lambda_role.arn}"
  handler          = "lambda_handler"
  source_code_hash = "${data.archive_file.get_posts_pkg.output_base64sha256}"
  runtime          = "python3.6"
  tags = "${merge(local.global_tags,map("Name", "get_posts"))}"

  environment {
    variables = {
      DB_TABLE_NAME = "${aws_dynamodb_table.meggie_db.name}"
    }
  }
}

data "archive_file" "convert_audio_pkg" {
  type = "zip"
  source_file = "${path.module}/lambda/converttoaudio.py"
  output_path = "${path.module}/target/converttoaudio.zip"
}
resource "aws_lambda_function" "convert_to_audio" {
  filename         = "${data.archive_file.convert_audio_pkg.output_path}"
  function_name    = "Meggie_ConvertToAudio"
  role             = "${aws_iam_role.lambda_role.arn}"
  handler          = "lambda_handler"
  source_code_hash = "${data.archive_file.convert_audio_pkg.output_base64sha256}"
  runtime          = "python3.6"
  tags = "${merge(local.global_tags,map("Name", "convert_to_audio"))}"

  environment {
    variables = {
      DB_TABLE_NAME = "${aws_dynamodb_table.meggie_db.name}"
      BUCKET_NAME = "${var.mp3_bucket}"
    }
  }
}

