# SendGrid Web API Delivery Method for ActionMailer
#
# This delivery method uses SendGrid's REST API v3 instead of SMTP.
# It provides better performance, reliability, and features like:
# - Better error handling and reporting
# - Webhook support for delivery tracking
# - Better handling of attachments and multipart emails
#
# Configuration:
#   Set SENDGRID_API_KEY environment variable with your SendGrid API key
#   Optionally set SENDGRID_API_HOST (defaults to https://api.sendgrid.com)
#
# Usage:
#   The delivery method is automatically selected when SENDGRID_API_KEY is present.
#   Otherwise, the application falls back to SMTP.
#
module ActionMailer
  module DeliveryMethods
    class SendgridApi
      require 'net/http'
      require 'uri'
      require 'json'

      def initialize(settings)
        @api_key = settings[:api_key] || ENV['SENDGRID_API_KEY']
        @api_host = settings[:api_host] || 'https://api.sendgrid.com'
        raise ArgumentError, 'SENDGRID_API_KEY is required' unless @api_key
      end

      def deliver!(mail)
        uri = URI.parse("#{@api_host}/v3/mail/send")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri.path)
        request['Authorization'] = "Bearer #{@api_key}"
        request['Content-Type'] = 'application/json'

        request.body = build_payload(mail).to_json

        response = http.request(request)

        if response.code.to_i >= 400
          error_message = "SendGrid API error: #{response.code} - #{response.body}"
          Rails.logger.error(error_message)
          raise StandardError, error_message
        end

        Rails.logger.info("Email sent via SendGrid API: #{mail.to} - Message ID: #{response['X-Message-Id']}")
        response
      end

      private

      def build_payload(mail)
        payload = {
          personalizations: [{
            to: extract_addresses(mail.to),
            subject: mail.subject
          }],
          from: extract_from_address(mail.from),
          content: []
        }

        # Handle multipart emails (both HTML and text)
        if mail.multipart?
          if mail.html_part
            payload[:content] << {
              type: 'text/html',
              value: mail.html_part.body.to_s
            }
          end
          if mail.text_part
            payload[:content] << {
              type: 'text/plain',
              value: mail.text_part.body.to_s
            }
          end
        else
          # Single part email
          payload[:content] << {
            type: determine_content_type(mail),
            value: extract_body(mail)
          }
        end

        # Add CC if present
        if mail.cc.present?
          payload[:personalizations][0][:cc] = extract_addresses(mail.cc)
        end

        # Add BCC if present
        if mail.bcc.present?
          payload[:personalizations][0][:bcc] = extract_addresses(mail.bcc)
        end

        # Add Reply-To if present
        if mail.reply_to.present?
          payload[:reply_to] = extract_address(mail.reply_to.first)
        end

        # Add custom headers if present
        if mail.headers.present?
          payload[:headers] = mail.headers
        end

        # Add attachments if present
        if mail.attachments.any?
          payload[:attachments] = mail.attachments.map do |attachment|
            {
              content: Base64.strict_encode64(attachment.body.to_s),
              filename: attachment.filename,
              type: attachment.content_type,
              disposition: 'attachment'
            }
          end
        end

        payload
      end

      def extract_addresses(addresses)
        Array(addresses).map { |addr| extract_address(addr) }
      end

      def extract_address(address)
        if address.is_a?(String)
          # Parse "Name <email@example.com>" format
          if address.match?(/^(.+?)\s*<(.+?)>$/)
            name = $1.strip
            email = $2.strip
            { email: email, name: name }
          else
            { email: address }
          end
        else
          { email: address.address, name: address.display_name }
        end
      end

      def extract_from_address(from)
        extract_address(from.first || from)
      end

      def determine_content_type(mail)
        if mail.html_part || mail.content_type&.include?('text/html')
          'text/html'
        elsif mail.text_part || mail.content_type&.include?('text/plain')
          'text/plain'
        else
          'text/plain'
        end
      end

      def extract_body(mail)
        if mail.html_part
          mail.html_part.body.to_s
        elsif mail.text_part
          mail.text_part.body.to_s
        else
          mail.body.to_s
        end
      end
    end
  end
end

# Register the delivery method
ActionMailer::Base.add_delivery_method :sendgrid_api, ActionMailer::DeliveryMethods::SendgridApi

