class TrendRunHistory < ApplicationRecord
  validates :trend, presence: true
  validates :trend_slug, presence: true

  scope :used_since, ->(cutoff) { where("created_at >= ?", cutoff).pluck(:trend_slug).to_set }

  def self.fresh?(slug, cooldown_hours)
    !used_since(cooldown_hours.hours.ago).include?(slug)
  end

  def self.slugify(text)
    cleaned = clean(text)
    slug = cleaned.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    return slug if slug.present?

    fallback_seed = Digest::SHA1.hexdigest(cleaned)[0, 12]
    "trend-#{fallback_seed}"
  end

  def self.clean(text)
    text.to_s.strip.gsub(/\s+/, " ")
  end
end
