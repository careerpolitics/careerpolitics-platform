# frozen_string_literal: true

ActionMailer::Base.add_delivery_method(
  :sendgrid_api,
  SendgridApiDelivery,
  api_key: ENV["SENDGRID_API_KEY"]
)

