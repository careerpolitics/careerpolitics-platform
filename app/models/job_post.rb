class JobPost < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :post_type, inclusion: { in: %w[new_update admit_card online_form] }, allow_nil: true
  validates :link, presence: true, if: :published?
  validate :link_format, if: :published?

  def link_format
    return if link.blank?
    # Allow relative URLs (starting with /) or absolute URLs (http/https)
    return if link.start_with?('/') || link.match?(/\Ahttps?:\/\//)
    errors.add(:link, 'must be a valid URL (starting with http://, https://, or /)')
  end

  before_validation :generate_slug, on: :create
  before_save :set_published_at, if: :published_changed?

  scope :published, -> { where(published: true) }
  scope :approved, -> { where(approved: true) }
  scope :available, -> { published.approved }
  scope :by_post_type, ->(type) { where(post_type: type) }
  scope :recent, -> { order(position: :asc, published_at: :desc, created_at: :desc) }
  scope :featured, -> { available.where(featured: true).recent.limit(8) }
  scope :pending_approval, -> { where(approved: false) }

  POST_TYPES = {
    new_update: 'new_update',
    admit_card: 'admit_card',
    online_form: 'online_form'
  }.freeze

  def to_param
    slug
  end

  def path
    "/jobs/#{slug}"
  end

  def badge_type
    return nil unless published_at
    # New badge: published within last 3 days
    return 'new' if published_at > 3.days.ago
    # Last day badge: if there's a deadline and it's within 24 hours
    # Note: This assumes link might contain deadline info, or you can add a deadline_date field
    nil
  end

  def related_jobs(limit: 4)
    JobPost.available
      .where.not(id: id)
      .where(post_type: post_type)
      .recent
      .limit(limit)
  end

  def available?
    published? && approved?
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
