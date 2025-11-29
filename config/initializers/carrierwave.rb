require "mini_magick"

# Carrierwave uses MiniMagick for image processing. To prevent server timeouts
# we are setting the MiniMagick timeout lower.
MiniMagick.configure do |config|
  config.timeout = 10
end

module CarrierWaveInitializer
  def self.local_storage_config
    CarrierWave.configure do |config|
      config.storage = :file
      config.enable_processing = !Rails.env.test? # disabled for test
      config.asset_host = if Rails.env.production?
                            "https://#{ApplicationConfig['APP_DOMAIN']}"
                          end
    end
  end

  def self.standard_production_config
    CarrierWave.configure do |config|
      config.storage = :fog
      config.fog_directory = ApplicationConfig["AWS_BUCKET_NAME"]
      config.fog_provider = "fog/aws"
      config.fog_attributes = { cache_control: "public, max-age=#{365.days.to_i}" }
      
      # DigitalOcean Spaces is S3-compatible - use DO credentials if available, otherwise AWS
      access_key_id = ApplicationConfig["DO_SPACES_ACCESS_KEY_ID"].presence || ApplicationConfig["AWS_ID"]
      secret_access_key = ApplicationConfig["DO_SPACES_SECRET_ACCESS_KEY"].presence || ApplicationConfig["AWS_SECRET"]
      spaces_endpoint = ApplicationConfig["DO_SPACES_ENDPOINT"]
      spaces_region = ApplicationConfig["AWS_UPLOAD_REGION"].presence || "sgp1"
      
      credentials = {
        provider: "AWS",
        aws_access_key_id: access_key_id,
        aws_secret_access_key: secret_access_key,
        region: spaces_region
      }
      
      # Add endpoint only for DigitalOcean Spaces (not needed for AWS)
      credentials[:endpoint] = spaces_endpoint if spaces_endpoint.present?
      
      config.fog_credentials = credentials
    end
  end

  def self.forem_cloud_config
    CarrierWave.configure do |config|
      config.storage = :fog
      config.fog_directory = ApplicationConfig["AWS_BUCKET_NAME"]
      config.fog_provider = "fog/aws"
      config.asset_host = "https://#{ApplicationConfig['APP_DOMAIN']}/remoteimages"
      config.fog_public = false
      config.fog_credentials = {
        provider: "AWS",
        use_iam_profile: true,
        region: "us-east-2"
      }
    end
  end

  def self.initialize!
    if Rails.env.production? && ENV["FILE_STORAGE_LOCATION"] != "file"
      if ENV["FOREM_CONTEXT"] == "forem_cloud"
        forem_cloud_config
      elsif ApplicationConfig["AWS_ID"].present? || ApplicationConfig["DO_SPACES_ACCESS_KEY_ID"].present?
        standard_production_config
      else
        local_storage_config
      end
    else
      local_storage_config
    end
  end
end

Rails.application.reloader.to_prepare do
  CarrierWaveInitializer.initialize!
end
