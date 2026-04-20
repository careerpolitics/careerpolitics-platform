class TrendRunHistory < ApplicationRecord
  validates :trend, presence: true
  validates :trend_slug, presence: true

  scope :used_since, ->(cutoff) { where("created_at >= ?", cutoff).pluck(:trend_slug).to_set }

  def self.fresh?(slug, cooldown_hours)
    !used_since(cooldown_hours.hours.ago).include?(slug)
  end

  def self.slugify(text)
    text.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
  end

  def self.clean(text)
    text.to_s.strip.gsub(/\s+/, " ")
  end
end
