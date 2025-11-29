# @forem/systems: We only can load this if video flow is entirely configured in AWS.
# Which is something we're currently punting on to rethink.
# As far as we know this only works and is supported on dev.to and not other forems.

S3DirectUpload.config do |c|
  if Rails.env.test?
    ENV["AWS_S3_VIDEO_ID"] = "available"
    ENV["AWS_S3_VIDEO_KEY"] = "available"
    ENV["AWS_S3_INPUT_BUCKET"] = "available"
  end
  # Support both AWS S3 and DigitalOcean Spaces
  c.access_key_id = ENV.fetch("AWS_S3_VIDEO_ID", ENV.fetch("DO_SPACES_ACCESS_KEY_ID", nil))
  c.secret_access_key = ENV.fetch("AWS_S3_VIDEO_KEY", ENV.fetch("DO_SPACES_SECRET_ACCESS_KEY", nil))
  c.bucket = ENV.fetch("AWS_S3_INPUT_BUCKET", ENV.fetch("AWS_BUCKET_NAME", nil))
  
  # For DigitalOcean Spaces, set region and endpoint
  if ENV["DO_SPACES_ENDPOINT"].present?
    spaces_region = ENV.fetch("AWS_UPLOAD_REGION", "sgp1")
    c.region = spaces_region
    c.url = "#{ENV['DO_SPACES_ENDPOINT']}/#{c.bucket}"
  else
    # AWS S3 configuration
    c.region = nil # region prefix. _Required_ for non-default AWS region, eg. "eu-west-1"
    c.url = nil # S3 API endpoint (optional), eg. "https://#{c.bucket}.s3.amazonaws.com"
  end
end
