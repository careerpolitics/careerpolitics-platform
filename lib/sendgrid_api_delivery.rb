# frozen_string_literal: true
require "base64"
require "sendgrid-ruby"

# Custom ActionMailer delivery method for SendGrid Web API v3
# Uses direct API calls instead of SMTP for better deliverability & features
#
# Usage:
#   config.action_mailer.delivery_method = :sendgrid_api
#
class SendgridApiDelivery
  include SendGrid

  attr_accessor :settings

  def initialize(settings = {})
    @settings = {
      api_key: ENV["SENDGRID_API_KEY"],
      raise_delivery_errors: true
    }.merge(settings)
  end

  # Called automatically by ActionMailer
  def deliver!(mail)
    sg_mail = build_sendgrid_mail(mail)
    client = SendGrid::API.new(api_key: settings[:api_key])

    response = client.client.mail._("send").post(request_body: sg_mail.to_json)

    unless response.status_code.start_with?("2")
      raise_delivery_error(response)
    end

    response
  end

  private

  def build_sendgrid_mail(mail)
    sg_mail = SendGrid::Mail.new

    sg_mail.from = Email.new(email: mail.from.first)

    mail.to.each do |to_email|
      sg_mail.add_to(Email.new(email: to_email))
    end

    sg_mail.subject = mail.subject

    add_content(sg_mail, mail)
    add_attachments(sg_mail, mail)
    add_headers(sg_mail, mail)

    sg_mail
  end

  def add_content(sg_mail, mail)
    if mail.html_part
      sg_mail.add_content(
        Content.new(type: "text/html", value: mail.html_part.body.decoded)
      )
    end

    if mail.text_part
      sg_mail.add_content(
        Content.new(type: "text/plain", value: mail.text_part.body.decoded)
      )
    end

    # Fallback for simple mails
    if mail.html_part.nil? && mail.text_part.nil?
      sg_mail.add_content(
        Content.new(type: "text/plain", value: mail.body.decoded)
      )
    end
  end

  def add_attachments(sg_mail, mail)
    mail.attachments.each do |attachment|
      sg_mail.add_attachment(
        Attachment.new(
          content: Base64.strict_encode64(attachment.body.decoded),
          filename: attachment.filename,
          type: attachment.mime_type,
          disposition: "attachment"
        )
      )
    end
  end

  def add_headers(sg_mail, mail)
    return if mail.headers.empty?

    allowed = %w[X-Entity-Ref-ID X-Campaign-ID]
    headers = mail.headers.to_h
                  .select { |k, _| allowed.include?(k) }
                  .transform_values(&:value)

    sg_mail.headers = headers unless headers.empty?
  end

end

