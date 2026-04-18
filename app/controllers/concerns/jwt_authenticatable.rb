# frozen_string_literal: true

module JwtAuthenticatable
  extend ActiveSupport::Concern

  private

  def generate_auth_token(user, expires_in: 5.minutes)
    payload = {
      user_id: user.id,
      exp: expires_in.from_now.to_i
    }
    JWT.encode(payload, Rails.application.secret_key_base)
  end

  def decode_auth_token(token)
    JWT.decode(token, Rails.application.secret_key_base, true, algorithm: "HS256")[0]
  rescue JWT::ExpiredSignature, JWT::DecodeError
    nil
  end
end
