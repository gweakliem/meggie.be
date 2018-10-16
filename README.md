# Meggie.be - Alexa skill and management website

This is based off the A Cloud Guru "Teach yourself AWS with Lambda and Polly" lessons. 

# Deployment

Deployment is done via terraform in the usual way:

```bash
terraform apply
```

Terraform assumes that you have 2 buckets created already, one to host the static website (following the rules for
S3 website hosting, that is named after the apex domain), the 2nd for hosting the converted MP3 output from Polly.

