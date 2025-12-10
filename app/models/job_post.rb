class JobPost < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :post_type, inclusion: { in: %w[new_update admit_card online_form] }, allow_nil: true

  before_validation :generate_slug, on: :create
  before_save :set_published_at, if: :published_changed?

  scope :published, -> { where(published: true) }
  scope :by_post_type, ->(type) { where(post_type: type) }
  scope :recent, -> { order(published_at: :desc, created_at: :desc) }
  scope :featured, -> { published.recent.limit(8) }

  POST_TYPES = {
    new_update: 'new_update',
    admit_card: 'admit_card',
    online_form: 'online_form'
  }.freeze

  def to_param
    slug
  end

  def path
    "/job-posts/#{slug}"
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = title.parameterize
    self.slug = base_slug
    counter = 1
    while JobPost.exists?(slug: self.slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def set_published_at
    self.published_at = Time.current if published? && published_at.nil?
  end
end
