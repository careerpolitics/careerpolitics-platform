# config/initializers/sendgrid_api_delivery.rb
# frozen_string_literal: true

require Rails.root.join("lib/sendgrid_api_delivery")

ActionMailer::Base.add_delivery_method(
  :sendgrid_api,
  SendgridApiDelivery,
  api_key: ENV["SENDGRID_API_KEY"]
)
