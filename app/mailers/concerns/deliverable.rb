module Deliverable
  extend ActiveSupport::Concern

  included do
    before_action :set_perform_deliveries
    after_action  :set_delivery_options
  end

  def set_perform_deliveries
    self.perform_deliveries = ForemInstance.smtp_enabled?
  end

  def set_delivery_options
    if ForemInstance.sendgrid_enabled?
      mail.delivery_method :sendgrid_api, api_key: ENV["SENDGRID_API_KEY"]
    else
      mail.delivery_method :smtp, Settings::SMTP.settings
    end
  end

end
